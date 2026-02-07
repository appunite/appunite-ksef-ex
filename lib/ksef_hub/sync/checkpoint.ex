defmodule KsefHub.Sync.Checkpoint do
  @moduledoc "Sync checkpoint schema. Tracks the last synced timestamp per NIP and direction."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(income expense)

  schema "sync_checkpoints" do
    field :checkpoint_type, :string
    field :last_seen_timestamp, :utc_datetime_usec
    field :nip, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  @doc "Builds a changeset for checkpoint creation/update."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [:checkpoint_type, :last_seen_timestamp, :nip, :metadata])
    |> validate_required([:checkpoint_type, :last_seen_timestamp, :nip])
    |> validate_inclusion(:checkpoint_type, @valid_types)
    |> validate_format(:nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> unique_constraint([:checkpoint_type, :nip])
  end
end
