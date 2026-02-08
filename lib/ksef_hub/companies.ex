defmodule KsefHub.Companies do
  @moduledoc """
  The Companies context. Manages company entities identified by NIP.
  """

  import Ecto.Query

  alias KsefHub.Companies.Company
  alias KsefHub.Repo

  @doc "Lists all companies ordered by name."
  @spec list_companies() :: [Company.t()]
  def list_companies do
    Company
    |> order_by([c], asc: c.name)
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
end
