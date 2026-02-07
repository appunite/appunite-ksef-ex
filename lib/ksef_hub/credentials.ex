defmodule KsefHub.Credentials do
  @moduledoc """
  The Credentials context. Manages KSeF certificate storage and encryption.
  """

  import Ecto.Query
  alias KsefHub.Repo
  alias KsefHub.Credentials.Credential

  def get_credential!(id), do: Repo.get!(Credential, id)

  def get_credential(id), do: Repo.get(Credential, id)

  @doc """
  Returns the active credential, if any.
  """
  def get_active_credential do
    Credential
    |> where([c], c.is_active == true)
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Lists all credentials.
  """
  def list_credentials do
    Credential
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a new credential.
  """
  def create_credential(attrs) do
    %Credential{}
    |> Credential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a credential.
  """
  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deactivates a credential.
  """
  def deactivate_credential(%Credential{} = credential) do
    update_credential(credential, %{is_active: false})
  end

  @doc """
  Updates the last sync timestamp for a credential.
  """
  def update_last_sync(%Credential{} = credential) do
    update_credential(credential, %{last_sync_at: DateTime.utc_now()})
  end

  @doc """
  Stores token information on a credential after KSeF authentication.
  """
  def store_tokens(%Credential{} = credential, attrs) do
    update_credential(credential, attrs)
  end
end
