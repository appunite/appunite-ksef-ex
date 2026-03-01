defmodule KsefHub.Files.File do
  @moduledoc "Schema for immutable file storage. Stores binary content with metadata."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_bytes 10_000_000

  schema "files" do
    field :content, :binary
    field :content_type, :string
    field :filename, :string
    field :byte_size, :integer

    timestamps(updated_at: false)
  end

  @doc "Builds a changeset for creating a file."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:content, :content_type, :filename])
    |> validate_required([:content, :content_type])
    |> compute_byte_size()
    |> validate_number(:byte_size,
      less_than_or_equal_to: @max_bytes,
      message: "must be at most 10MB"
    )
  end

  @spec compute_byte_size(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp compute_byte_size(changeset) do
    case get_change(changeset, :content) do
      nil -> changeset
      content when is_binary(content) -> put_change(changeset, :byte_size, byte_size(content))
      _ -> changeset
    end
  end
end
