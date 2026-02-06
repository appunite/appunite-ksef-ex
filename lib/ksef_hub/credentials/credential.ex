defmodule KsefHub.Credentials.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ksef_credentials" do
    field :nip, :string
    field :certificate_data, :binary
    field :certificate_password_encrypted, :binary
    field :certificate_expires_at, :date
    field :certificate_subject, :string
    field :last_sync_at, :utc_datetime_usec
    field :is_active, :boolean, default: true
    field :refresh_token_encrypted, :binary
    field :refresh_token_expires_at, :utc_datetime_usec
    field :access_token, :string
    field :access_token_expires_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :nip, :certificate_data, :certificate_password_encrypted,
      :certificate_expires_at, :certificate_subject, :last_sync_at,
      :is_active, :refresh_token_encrypted, :refresh_token_expires_at,
      :access_token, :access_token_expires_at
    ])
    |> validate_required([:nip])
    |> validate_format(:nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
  end
end
