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
    |> join(:inner, [c], m in Membership, on: m.company_id == c.id and m.user_id == ^user_id)
    |> where([c], c.is_active == true)
    |> order_by([c], asc: c.name)
    |> select_merge([c], %{has_active_credential: exists(subquery(active_cred_subquery))})
    |> Repo.all()
  end

  @doc "Lists active companies for a given user, ordered by name."
  @spec list_companies_for_user(Ecto.UUID.t()) :: [Company.t()]
  def list_companies_for_user(user_id) do
    Membership
    |> where([m], m.user_id == ^user_id)
    |> join(:inner, [m], c in Company, on: c.id == m.company_id and c.is_active == true)
    |> order_by([m, c], asc: c.name)
    |> select([m, c], c)
    |> Repo.all()
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
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        company_id: company.id,
        role: "owner"
      })
    end)
    |> Repo.transaction()
  end

  # ---------------------------------------------------------------------------
  # Membership queries
  # ---------------------------------------------------------------------------

  @doc "Fetches the membership for a user+company pair, returning nil if none exists."
  @spec get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: Membership.t() | nil
  def get_membership(user_id, company_id) do
    Repo.get_by(Membership, user_id: user_id, company_id: company_id)
  end

  @doc "Fetches the membership for a user+company pair, raising if not found."
  @spec get_membership!(Ecto.UUID.t(), Ecto.UUID.t()) :: Membership.t()
  def get_membership!(user_id, company_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id)
    |> Repo.one!()
  end

  @doc "Creates a membership."
  @spec create_membership(map()) :: {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  def create_membership(attrs) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks whether a user has a specific role (or one of a list of roles) for a company.
  """
  @spec has_role?(Ecto.UUID.t(), Ecto.UUID.t(), String.t() | [String.t()]) :: boolean()
  def has_role?(user_id, company_id, role_or_roles) do
    roles = List.wrap(role_or_roles)

    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id)
    |> where([m], m.role in ^roles)
    |> Repo.exists?()
  end

  @doc """
  Authorizes a user for a company with the given required roles.
  Returns `{:ok, membership}` or `{:error, :unauthorized}`.
  """
  @spec authorize(Ecto.UUID.t(), Ecto.UUID.t(), [String.t()]) ::
          {:ok, Membership.t()} | {:error, :unauthorized}
  def authorize(user_id, company_id, required_roles) do
    Membership
    |> where([m], m.user_id == ^user_id and m.company_id == ^company_id)
    |> where([m], m.role in ^required_roles)
    |> Repo.one()
    |> case do
      %Membership{} = membership -> {:ok, membership}
      nil -> {:error, :unauthorized}
    end
  end
end
