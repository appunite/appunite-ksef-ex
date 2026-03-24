defmodule KsefHub.Companies do
  @moduledoc """
  The Companies context. Manages company entities identified by NIP
  and user-company memberships with role-based access control.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias KsefHub.Accounts.User
  alias KsefHub.Companies.{Company, Membership}
  alias KsefHub.Repo

  # ---------------------------------------------------------------------------
  # Company queries
  # ---------------------------------------------------------------------------

  @doc "Lists all active companies ordered by name."
  @spec list_companies() :: [Company.t()]
  def list_companies do
    Company
    |> where([c], c.is_active == true)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Lists all companies with a boolean `has_active_credential` virtual field.
  Uses a single query with a subquery instead of N+1 credential lookups.
  """
  @spec list_companies_with_credential_status() :: [map()]
  def list_companies_with_credential_status do
    active_cred_subquery =
      from(cr in KsefHub.Credentials.Credential,
        where: cr.company_id == parent_as(:company).id and cr.is_active == true,
        select: 1
      )

    Company
    |> from(as: :company)
    |> order_by([c], asc: c.name)
    |> select_merge([c], %{has_active_credential: exists(subquery(active_cred_subquery))})
    |> Repo.all()
  end

  @doc """
  Lists active companies for a given user (through memberships), with credential status.
  Replaces `list_companies_with_credential_status/0` for membership-scoped access.
  """
  @spec list_companies_for_user_with_credential_status(Ecto.UUID.t()) :: [map()]
  def list_companies_for_user_with_credential_status(user_id) do
    active_cred_subquery =
      from(cr in KsefHub.Credentials.Credential,
        where: cr.company_id == parent_as(:company).id and cr.is_active == true,
        select: 1
      )

    Company
    |> from(as: :company)
    |> join(:inner, [c], m in Membership,
      on: m.company_id == c.id and m.user_id == ^user_id and m.status == :active
    )
    |> where([c], c.is_active == true)
    |> order_by([c], asc: c.name)
    |> select_merge([c], %{has_active_credential: exists(subquery(active_cred_subquery))})
    |> Repo.all()
  end

  @doc "Lists active companies for a given user (active memberships only), ordered by name."
  @spec list_companies_for_user(Ecto.UUID.t()) :: [Company.t()]
  def list_companies_for_user(user_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.status == :active)
    |> join(:inner, [m], c in Company, on: c.id == m.company_id and c.is_active == true)
    |> order_by([m, c], asc: c.name)
    |> select([m, c], c)
    |> Repo.all()
  end

  @doc "Returns the first company ID for a user, or nil if the user has no companies."
  @spec first_company_id_for_user(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def first_company_id_for_user(user_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.status == :active)
    |> join(:inner, [m], c in Company, on: c.id == m.company_id and c.is_active == true)
    |> order_by([m, c], asc: c.name, asc: c.id)
    |> select([m, c], c.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Fetches a company by ID, raising if not found."
  @spec get_company!(Ecto.UUID.t()) :: Company.t()
  def get_company!(id), do: Repo.get!(Company, id)

  @doc "Fetches a company by ID, returning nil if not found."
  @spec get_company(Ecto.UUID.t()) :: Company.t() | nil
  def get_company(id), do: Repo.get(Company, id)

  @doc "Creates a new company."
  @spec create_company(map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def create_company(attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an existing company."
  @spec update_company(Company.t(), map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def update_company(%Company{} = company, attrs) do
    company
    |> Company.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a company and an owner membership for the given user in a single transaction.
  Returns `{:ok, %{company: company, membership: membership}}` on success.
  """
  @spec create_company_with_owner(User.t(), map()) ::
          {:ok, %{company: Company.t(), membership: Membership.t()}}
          | {:error, atom(), Ecto.Changeset.t(), map()}
  def create_company_with_owner(%User{} = user, attrs) do
    Multi.new()
    |> Multi.insert(:company, Company.changeset(%Company{}, attrs))
    |> Multi.insert(:membership, fn %{company: company} ->
      %Membership{user_id: user.id, company_id: company.id}
      |> Membership.changeset(%{role: :owner})
    end)
    |> Repo.transaction()
  end

  @doc "Updates inbound email settings (allowed sender domain, CC email) for a company."
  @spec update_inbound_email_settings(Company.t(), map()) ::
          {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def update_inbound_email_settings(%Company{} = company, attrs) do
    company
    |> Company.inbound_email_settings_changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Inbound email token management
  # ---------------------------------------------------------------------------

  @doc """
  Generates and sets a random 8-char alphanumeric inbound email token for a company.

  Both the plaintext token and its SHA-256 hash are persisted — the plaintext is
  stored so the full email address can always be displayed in the UI.
  """
  @spec enable_inbound_email(Company.t()) ::
          {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def enable_inbound_email(%Company{} = company) do
    plaintext = generate_inbound_token()
    token_hash = hash_inbound_token(plaintext)

    company
    |> Company.inbound_email_token_changeset(%{token: plaintext, hash: token_hash})
    |> Repo.update()
  end

  @doc "Clears the inbound email token and hash, disabling email intake for the company."
  @spec disable_inbound_email(Company.t()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def disable_inbound_email(%Company{} = company) do
    company
    |> Company.inbound_email_token_changeset(%{token: nil, hash: nil})
    |> Repo.update()
  end

  @doc "Looks up an active company by its inbound email token (hashed for comparison)."
  @spec get_company_by_inbound_email_token(String.t() | nil) :: Company.t() | nil
  def get_company_by_inbound_email_token(nil), do: nil

  def get_company_by_inbound_email_token(token) when is_binary(token) do
    token_hash = hash_inbound_token(token)

    Company
    |> where([c], c.inbound_email_token_hash == ^token_hash and c.is_active == true)
    |> Repo.one()
  end

  @spec generate_inbound_token() :: String.t()
  defp generate_inbound_token do
    :crypto.strong_rand_bytes(6)
    |> Base.encode32(case: :lower, padding: false)
    |> binary_part(0, 8)
  end

  @spec hash_inbound_token(String.t()) :: String.t()
  defp hash_inbound_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Membership queries
  # ---------------------------------------------------------------------------

  @doc "Lists all memberships for a company with preloaded users, ordered by role then name."
  @spec list_members(Ecto.UUID.t()) :: [Membership.t()]
  def list_members(company_id) do
    Membership
    |> where([m], m.company_id == ^company_id)
    |> join(:inner, [m], u in assoc(m, :user))
    |> order_by([m, u], asc: m.role, asc: u.name)
    |> preload([m, u], user: u)
    |> Repo.all()
  end

  @doc "Deletes a membership."
  @spec delete_membership(Membership.t()) :: {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def delete_membership(%Membership{} = membership) do
    Repo.delete(membership)
  end

  @doc "Updates the role of a membership."
  @spec update_membership_role(Membership.t(), Membership.role()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def update_membership_role(%Membership{} = membership, role) do
    membership
    |> Membership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc "Blocks a membership (soft delete)."
  @spec block_member(Membership.t()) :: {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def block_member(%Membership{} = membership) do
    membership
    |> Membership.status_changeset(%{status: :blocked})
    |> Repo.update()
  end

  @doc "Unblocks a membership, restoring active status."
  @spec unblock_member(Membership.t()) :: {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def unblock_member(%Membership{} = membership) do
    membership
    |> Membership.status_changeset(%{status: :active})
    |> Repo.update()
  end

  @doc "Fetches the active membership for a user+company pair, returning nil if none exists or blocked."
  @spec get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: Membership.t() | nil
  def get_membership(user_id, company_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id and m.status == :active)
    |> Repo.one()
  end

  @doc "Fetches the active membership for a user+company pair, raising if not found."
  @spec get_membership!(Ecto.UUID.t(), Ecto.UUID.t()) :: Membership.t()
  def get_membership!(user_id, company_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id and m.status == :active)
    |> Repo.one!()
  end

  @doc "Fetches a membership by ID with preloaded user (any status), for the detail page."
  @spec get_membership_with_user(Ecto.UUID.t(), Ecto.UUID.t()) :: Membership.t() | nil
  def get_membership_with_user(membership_id, company_id) do
    Membership
    |> where([m], m.id == ^membership_id and m.company_id == ^company_id)
    |> preload(:user)
    |> Repo.one()
  end

  @doc """
  Creates a membership. The `user_id` and `company_id` must be provided in `attrs`
  and are set directly on the struct (not cast from user input).
  """
  @spec create_membership(map()) :: {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def create_membership(attrs) do
    %Membership{
      user_id: attrs[:user_id] || attrs["user_id"],
      company_id: attrs[:company_id] || attrs["company_id"]
    }
    |> Membership.changeset(Map.take(attrs, [:role, "role"]))
    |> Repo.insert()
  end

  @doc """
  Checks whether a user has a specific role (or one of a list of roles) for a company.
  """
  @spec has_role?(Ecto.UUID.t(), Ecto.UUID.t(), Membership.role() | [Membership.role()]) ::
          boolean()
  def has_role?(user_id, company_id, role_or_roles) do
    roles = List.wrap(role_or_roles)

    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id and m.status == :active)
    |> where([m], m.role in ^roles)
    |> Repo.exists?()
  end

  @doc """
  Authorizes a user for a company with the given required roles.
  Returns `{:ok, membership}` or `{:error, :unauthorized}`.
  """
  @spec authorize(Ecto.UUID.t(), Ecto.UUID.t(), [Membership.role()]) ::
          {:ok, Membership.t()} | {:error, :unauthorized}
  def authorize(user_id, company_id, required_roles) do
    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id and m.status == :active)
    |> where([m], m.role in ^required_roles)
    |> Repo.one()
    |> case do
      %Membership{} = membership -> {:ok, membership}
      nil -> {:error, :unauthorized}
    end
  end
end
