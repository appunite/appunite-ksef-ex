defmodule KsefHub.Sync.Checkpoint do
  @moduledoc "Sync checkpoint schema. Tracks the last synced timestamp per company and direction."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type checkpoint_type :: :income | :expense

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_checkpoints" do
    field :checkpoint_type, Ecto.Enum, values: [:income, :expense]
    field :last_seen_timestamp, :utc_datetime_usec
    field :nip, :string
    field :metadata, :map, default: %{}

    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Returns the list of valid checkpoint types."
  @spec checkpoint_types() :: [checkpoint_type()]
  def checkpoint_types, do: Ecto.Enum.values(__MODULE__, :checkpoint_type)

  @doc "Builds a changeset for checkpoint creation/update."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [:checkpoint_type, :last_seen_timestamp, :nip, :metadata, :company_id])
    |> validate_required([:checkpoint_type, :last_seen_timestamp, :company_id])
    |> foreign_key_constraint(:company_id)
    |> unique_constraint([:checkpoint_type, :company_id])
  end
end
