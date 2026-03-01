defmodule KsefHub.Files do
  @moduledoc """
  The Files context. Manages immutable file storage for binary content
  (XML, PDF) referenced by invoices and inbound emails.
  """

  alias KsefHub.Files.File
  alias KsefHub.Repo

  @doc "Creates a file record with content, content_type, and optional filename."
  @spec create_file(map()) :: {:ok, File.t()} | {:error, Ecto.Changeset.t()}
  def create_file(attrs) do
    %File{}
    |> File.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Fetches a file by ID, raising if not found."
  @spec get_file!(Ecto.UUID.t()) :: File.t()
  def get_file!(id), do: Repo.get!(File, id)

  @doc "Fetches a file by ID, returning nil if not found."
  @spec get_file(Ecto.UUID.t()) :: File.t() | nil
  def get_file(id), do: Repo.get(File, id)
end
