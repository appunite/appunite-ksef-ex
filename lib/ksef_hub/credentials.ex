defmodule KsefHub.Credentials do
  @moduledoc """
  The Credentials context. Manages KSeF certificate storage and encryption.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias KsefHub.Credentials.Credential
  alias KsefHub.Repo

  @doc "Fetches a credential by ID, raising if not found."
  @spec get_credential!(Ecto.UUID.t()) :: Credential.t()
  def get_credential!(id), do: Repo.get!(Credential, id)

  @doc "Fetches a credential by ID, returning nil if not found."
  @spec get_credential(Ecto.UUID.t()) :: Credential.t() | nil
  def get_credential(id), do: Repo.get(Credential, id)

  @doc """
  Returns the active credential for a given company, if any.
  """
  @spec get_active_credential(Ecto.UUID.t()) :: Credential.t() | nil
  def get_active_credential(company_id) do
    Credential
    |> where([c], c.company_id == ^company_id and c.is_active == true)
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Lists all credentials for a given company.
  """
  @spec list_credentials(Ecto.UUID.t()) :: [Credential.t()]
  def list_credentials(company_id) do
    Credential
    |> where([c], c.company_id == ^company_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all active credentials across all companies.
  Used by SyncDispatcher to find companies that need syncing.
  """
  @spec list_active_credentials() :: [Credential.t()]
  def list_active_credentials do
    Credential
    |> where([c], c.is_active == true)
    |> preload(:company)
    |> Repo.all()
  end

  @doc """
  Creates a new credential. The `company_id` key in attrs is set server-side
  via `put_change` to prevent mass assignment.
  """
  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def create_credential(attrs) do
    company_id = attrs[:company_id] || attrs["company_id"]

    %Credential{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> Credential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atomically deactivates any existing active credential for the company
  and creates a new one. NIP is auto-populated from the company.
  """
  @spec replace_active_credential(Ecto.UUID.t(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def replace_active_credential(company_id, attrs) do
    company = KsefHub.Companies.get_company!(company_id)
    attrs = Map.merge(attrs, %{nip: company.nip})

    changeset =
      %Credential{}
      |> Ecto.Changeset.change(%{company_id: company_id})
      |> Credential.changeset(attrs)

    multi =
      Multi.new()
      |> Multi.run(:deactivate, fn _repo, _changes ->
        case get_active_credential(company_id) do
          nil -> {:ok, nil}
          existing -> deactivate_credential(existing)
        end
      end)
      |> Multi.insert(:credential, changeset)

    case Repo.transaction(multi) do
      {:ok, %{credential: credential}} -> {:ok, credential}
      {:error, :credential, changeset, _changes} -> {:error, changeset}
      {:error, :deactivate, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates a credential.
  """
  @spec update_credential(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deactivates a credential.
  """
  @spec deactivate_credential(Credential.t()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def deactivate_credential(%Credential{} = credential) do
    update_credential(credential, %{is_active: false})
  end

  @doc """
  Updates the last sync timestamp for a credential.
  """
  @spec update_last_sync(Credential.t()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def update_last_sync(%Credential{} = credential) do
    update_credential(credential, %{last_sync_at: DateTime.utc_now()})
  end

  @doc """
  Stores token information on a credential after KSeF authentication.
  """
  @spec store_tokens(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def store_tokens(%Credential{} = credential, attrs) do
    update_credential(credential, attrs)
  end
end
