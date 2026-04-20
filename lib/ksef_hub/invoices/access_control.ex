defmodule KsefHub.Invoices.AccessControl do
  @moduledoc """
  Access control for invoices.

  Manages access grants, restricted-invoice visibility, and role-based query
  scoping. Income invoices are always restricted so that reviewers cannot see
  them unless explicitly granted access.

  This module is used internally by `KsefHub.Invoices` — the public API facade
  delegates to the functions here. Query-scoping helpers (`maybe_filter_by_access/2`,
  `full_invoice_visibility?/1`, `access_scoped_invoice_query/1`) are called
  directly by listing functions that remain in the facade.
  """

  import Ecto.Query

  alias KsefHub.ActivityLog.Events
  alias KsefHub.ActivityLog.TrackedRepo
  alias KsefHub.Authorization
  alias KsefHub.Companies
  alias KsefHub.Companies.Membership
  alias KsefHub.Invoices.{Invoice, InvoiceAccessGrant}
  alias KsefHub.Repo

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Lists access grants for an invoice, with the grantee and granter users preloaded."
  @spec list_access_grants(Ecto.UUID.t()) :: [InvoiceAccessGrant.t()]
  def list_access_grants(invoice_id) do
    InvoiceAccessGrant
    |> where([g], g.invoice_id == ^invoice_id)
    |> preload([:user, :granted_by])
    |> order_by([g], asc: g.inserted_at)
    |> Repo.all()
  end

  @doc """
  Grants a user access to a restricted invoice. Idempotent — duplicate grants are silently ignored.

  Validates that the target user is a member of the same company as the invoice
  and does not have full invoice visibility (i.e. is a reviewer, not admin/owner/accountant).
  """
  @spec grant_access(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t() | nil, keyword()) ::
          {:ok, InvoiceAccessGrant.t()} | {:error, Ecto.Changeset.t()}
  def grant_access(invoice_id, user_id, granted_by_id \\ nil, opts \\ []) do
    with {:ok, company_id} <- fetch_invoice_company_id(invoice_id),
         {:ok, _membership} <- validate_grantable_member(company_id, user_id),
         :not_found <- existing_grant(invoice_id, user_id) do
      result =
        %InvoiceAccessGrant{}
        |> Ecto.Changeset.change(%{
          invoice_id: invoice_id,
          user_id: user_id,
          granted_by_id: granted_by_id
        })
        |> Ecto.Changeset.unique_constraint([:invoice_id, :user_id])
        |> Ecto.Changeset.foreign_key_constraint(:invoice_id)
        |> Ecto.Changeset.foreign_key_constraint(:user_id)
        |> Ecto.Changeset.foreign_key_constraint(:granted_by_id)
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:invoice_id, :user_id])

      case result do
        {:ok, grant} ->
          Events.invoice_access_granted(%{id: invoice_id, company_id: company_id}, user_id, opts)
          {:ok, grant}

        error ->
          error
      end
    end
  end

  defp existing_grant(invoice_id, user_id) do
    case Repo.get_by(InvoiceAccessGrant, invoice_id: invoice_id, user_id: user_id) do
      %InvoiceAccessGrant{} = grant -> {:ok, grant}
      nil -> :not_found
    end
  end

  @doc "Revokes a user's access to a restricted invoice."
  @spec revoke_access(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, InvoiceAccessGrant.t()} | {:error, :not_found}
  def revoke_access(invoice_id, user_id, opts \\ []) do
    InvoiceAccessGrant
    |> where([g], g.invoice_id == ^invoice_id and g.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      grant ->
        with {:ok, deleted} <- Repo.delete(grant) do
          emit_access_revoked(invoice_id, user_id, opts)
          {:ok, deleted}
        end
    end
  end

  @doc """
  Sets the access_restricted flag on an invoice.

  Income invoices cannot be unrestricted — they are always restricted by design
  so reviewers cannot see them unless explicitly granted access.
  """
  @spec set_access_restricted(Invoice.t(), boolean(), keyword()) ::
          {:ok, Invoice.t()} | {:error, :income_always_restricted | Ecto.Changeset.t()}
  def set_access_restricted(invoice, restricted, opts \\ [])

  def set_access_restricted(%Invoice{type: :income}, false, _opts),
    do: {:error, :income_always_restricted}

  def set_access_restricted(%Invoice{} = invoice, restricted, opts) when is_boolean(restricted) do
    invoice
    |> Ecto.Changeset.change(%{access_restricted: restricted})
    |> TrackedRepo.update(opts)
  end

  # -------------------------------------------------------------------
  # Query scoping (called from Invoices facade)
  # -------------------------------------------------------------------

  @doc false
  @spec maybe_filter_by_access(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  def maybe_filter_by_access(query, opts) do
    role = opts[:role]
    user_id = opts[:user_id]
    has_role_key = Keyword.has_key?(opts, :role)

    cond do
      # Role with full visibility — no filtering needed
      full_invoice_visibility?(role) ->
        query

      # Role specified with a user_id — filter by access grants
      is_binary(user_id) ->
        where(
          query,
          [i],
          i.access_restricted == false or
            i.id in subquery(
              from(g in InvoiceAccessGrant, where: g.user_id == ^user_id, select: g.invoice_id)
            )
        )

      # Internal/system calls (no role key at all) — no filtering
      not has_role_key ->
        query

      # Any other case — deny restricted invoices as a safety net
      true ->
        where(query, [i], i.access_restricted == false)
    end
  end

  @doc false
  @spec full_invoice_visibility?(Membership.role() | nil) :: boolean()
  def full_invoice_visibility?(nil), do: false
  def full_invoice_visibility?(role), do: Authorization.can?(role, :view_all_invoice_types)

  @doc false
  @spec access_scoped_invoice_query(keyword()) :: Ecto.Query.t()
  def access_scoped_invoice_query(opts) do
    from(i in Invoice) |> maybe_filter_by_access(opts)
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  @spec fetch_invoice_company_id(Ecto.UUID.t()) ::
          {:ok, Ecto.UUID.t()} | {:error, Ecto.Changeset.t()}
  defp fetch_invoice_company_id(invoice_id) do
    case Repo.get(Invoice, invoice_id) do
      %Invoice{company_id: cid} -> {:ok, cid}
      nil -> {:error, grant_error(:invoice_id, "invoice not found")}
    end
  end

  @spec validate_grantable_member(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  defp validate_grantable_member(company_id, user_id) do
    case Companies.get_membership(user_id, company_id) do
      %Membership{role: role} = m ->
        if full_invoice_visibility?(role),
          do: {:error, grant_error(:user_id, "user already has full access via their role")},
          else: {:ok, m}

      nil ->
        {:error, grant_error(:user_id, "user is not a member of this company")}
    end
  end

  @spec grant_error(atom(), String.t()) :: Ecto.Changeset.t()
  defp grant_error(field, message) do
    %InvoiceAccessGrant{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(field, message)
  end

  @spec emit_access_revoked(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: :ok
  defp emit_access_revoked(invoice_id, user_id, opts) do
    case Repo.get(Invoice, invoice_id) do
      %Invoice{company_id: company_id} ->
        Events.invoice_access_revoked(%{id: invoice_id, company_id: company_id}, user_id, opts)

      nil ->
        :ok
    end
  end
end
