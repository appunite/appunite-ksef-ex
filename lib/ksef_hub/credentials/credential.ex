defmodule KsefHub.Credentials.Credential do
  @moduledoc """
  KSeF credential schema. Stores company-level sync configuration and session tokens.

  Certificate data has been moved to `UserCertificate` (user-scoped) per ADR 0012.
  This table retains the NIP, token state, and sync timestamps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @behaviour KsefHub.ActivityLog.Trackable

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ksef_credentials" do
    field :nip, :string
    field :last_sync_at, :utc_datetime_usec
    field :is_active, :boolean, default: true
    field :refresh_token_encrypted, :binary
    field :refresh_token_expires_at, :utc_datetime_usec
    field :access_token_encrypted, :binary
    field :access_token_expires_at, :utc_datetime_usec

    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @cast_fields [
    :nip,
    :last_sync_at,
    :is_active,
    :refresh_token_encrypted,
    :refresh_token_expires_at,
    :access_token_encrypted,
    :access_token_expires_at
  ]

  @doc "Builds a changeset for credential creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, @cast_fields)
    |> validate_required([:nip, :company_id])
    |> validate_format(:nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> foreign_key_constraint(:company_id)
    |> unique_constraint(:company_id,
      name: :ksef_credentials_company_id_active_index,
      message: "already has an active credential"
    )
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_change(Ecto.Changeset.t()) :: {String.t(), map()} | :skip
  def track_change(%Ecto.Changeset{action: :insert}), do: {"credential.uploaded", %{}}

  def track_change(%Ecto.Changeset{} = cs) do
    case cs.changes do
      %{is_active: false} -> {"credential.invalidated", %{}}
      # Token/sync updates are internal bookkeeping, not user-facing events
      _ -> :skip
    end
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_delete(t()) :: :skip
  def track_delete(_credential), do: :skip
end
