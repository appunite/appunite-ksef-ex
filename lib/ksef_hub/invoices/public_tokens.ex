defmodule KsefHub.Invoices.PublicTokens do
  @moduledoc """
  Manages per-user public sharing tokens for invoices.

  Each token is scoped to a single (invoice, user) pair and expires after 30 days.
  A unique constraint on (invoice_id, user_id) ensures at most one active token
  per pair — concurrent calls converge on the same DB-canonical token via upsert.
  """

  import Ecto.Query

  alias KsefHub.Invoices.{Invoice, InvoicePublicToken}
  alias KsefHub.Repo

  @token_ttl_days 30

  @doc """
  Fetches an invoice by a valid (non-expired) public sharing token.

  Returns the invoice with company, xml_file, pdf_file, and category preloaded,
  or `nil` if the token is unknown, expired, or structurally invalid.
  """
  @spec get_invoice_by_public_token(String.t()) :: Invoice.t() | nil
  def get_invoice_by_public_token(token)
      when is_binary(token) and byte_size(token) in 20..100 do
    now = DateTime.utc_now()

    InvoicePublicToken
    |> where([pt], pt.token == ^token and pt.expires_at > ^now)
    |> preload(invoice: [:company, :xml_file, :pdf_file, :category])
    |> Repo.one()
    |> case do
      nil -> nil
      %InvoicePublicToken{invoice: invoice} -> invoice
    end
  end

  def get_invoice_by_public_token(_), do: nil

  @doc """
  Ensures a valid public sharing token exists for the given invoice and user.

  Returns an existing non-expired token if one exists, otherwise rotates
  (creates or replaces an expired one) via atomic upsert. The upsert guarantees
  that concurrent callers converge on the same DB-canonical token — both reload
  after the upsert so they receive the same value regardless of which write won.

  Returns `{:ok, token, :created}` when a new token was issued (suitable for
  emitting an activity log event) or `{:ok, token, :existing}` when reusing
  a still-valid one.
  """
  @spec ensure_public_token(Invoice.t(), Ecto.UUID.t()) ::
          {:ok, InvoicePublicToken.t(), :created | :existing} | {:error, Ecto.Changeset.t()}
  def ensure_public_token(%Invoice{} = invoice, user_id) when is_binary(user_id) do
    case get_valid_user_token(invoice.id, user_id) do
      %InvoicePublicToken{} = existing ->
        {:ok, existing, :existing}

      nil ->
        case rotate_public_token(invoice.id, user_id) do
          {:ok, pt} -> {:ok, pt, :created}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Deletes all public sharing tokens created by a user for invoices belonging
  to a given company. Called when a member is blocked to immediately invalidate
  any links they may have shared.
  """
  @spec delete_public_tokens_for_user(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
  def delete_public_tokens_for_user(user_id, company_id)
      when is_binary(user_id) and is_binary(company_id) do
    invoice_ids = from(i in Invoice, where: i.company_id == ^company_id, select: i.id)

    {count, _} =
      InvoicePublicToken
      |> where([pt], pt.user_id == ^user_id and pt.invoice_id in subquery(invoice_ids))
      |> Repo.delete_all()

    count
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec get_valid_user_token(Ecto.UUID.t(), Ecto.UUID.t()) :: InvoicePublicToken.t() | nil
  defp get_valid_user_token(invoice_id, user_id) do
    now = DateTime.utc_now()

    InvoicePublicToken
    |> where(
      [pt],
      pt.invoice_id == ^invoice_id and pt.user_id == ^user_id and pt.expires_at > ^now
    )
    |> Repo.one()
  end

  @spec rotate_public_token(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, InvoicePublicToken.t()} | {:error, Ecto.Changeset.t()}
  defp rotate_public_token(invoice_id, user_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at = DateTime.utc_now() |> DateTime.add(@token_ttl_days, :day) |> DateTime.truncate(:second)

    result =
      %InvoicePublicToken{}
      |> InvoicePublicToken.changeset(%{
        token: token,
        expires_at: expires_at,
        invoice_id: invoice_id,
        user_id: user_id
      })
      |> Repo.insert(
        on_conflict: {:replace, [:token, :expires_at, :inserted_at]},
        conflict_target: [:invoice_id, :user_id]
      )

    case result do
      {:ok, _} ->
        # Reload after upsert so concurrent callers both receive the DB-canonical token,
        # regardless of which write won the conflict resolution.
        {:ok, Repo.get_by!(InvoicePublicToken, invoice_id: invoice_id, user_id: user_id)}

      {:error, _} = err ->
        err
    end
  end
end
