defmodule KsefHub.Sync.Checkpoint do
  use Ecto.Schema
  import Ecto.Changeset

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

  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [:checkpoint_type, :last_seen_timestamp, :nip, :metadata])
    |> validate_required([:checkpoint_type, :last_seen_timestamp, :nip])
    |> validate_inclusion(:checkpoint_type, @valid_types)
    |> validate_format(:nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> unique_constraint([:checkpoint_type, :nip])
  end
end
