defmodule KsefHub.Credentials.Credential do
  @moduledoc "KSeF credential schema. Stores certificate data and session tokens."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ksef_credentials" do
    field :nip, :string
    field :certificate_data_encrypted, :binary
    field :certificate_password_encrypted, :binary
    field :certificate_expires_at, :date
    field :certificate_subject, :string
    field :last_sync_at, :utc_datetime_usec
    field :is_active, :boolean, default: true
    field :refresh_token_encrypted, :binary
    field :refresh_token_expires_at, :utc_datetime_usec
    field :access_token_encrypted, :binary
    field :access_token_expires_at, :utc_datetime_usec

    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Builds a changeset for credential creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :nip,
      :certificate_data_encrypted,
      :certificate_password_encrypted,
      :certificate_expires_at,
      :certificate_subject,
      :last_sync_at,
      :is_active,
      :refresh_token_encrypted,
      :refresh_token_expires_at,
      :access_token_encrypted,
      :access_token_expires_at
    ])
    |> validate_required([:nip, :company_id])
    |> validate_format(:nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> foreign_key_constraint(:company_id)
    |> unique_constraint(:company_id,
      name: :ksef_credentials_company_id_active_index,
      message: "already has an active credential"
    )
  end
end
