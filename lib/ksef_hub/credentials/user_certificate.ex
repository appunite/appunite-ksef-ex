defmodule KsefHub.Credentials.UserCertificate do
  @moduledoc """
  Schema for user-level KSeF certificates.

  A KSeF person certificate is tied to an individual (identified by PESEL),
  not to any company. One certificate authenticates for all companies where
  the person has KSeF authorization. The NIP in the `getChallenge` request
  determines the company context, not the certificate itself.

  This table stores the encrypted certificate data at the user level,
  eliminating the need to re-upload the same certificate for each company.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_certificates" do
    field :certificate_data_encrypted, :binary
    field :certificate_password_encrypted, :binary
    field :certificate_subject, :string
    field :not_before, :date
    field :not_after, :date
    field :fingerprint, :string
    field :is_active, :boolean, default: true

    belongs_to :user, KsefHub.Accounts.User

    timestamps()
  end

  @cast_fields [
    :certificate_data_encrypted,
    :certificate_password_encrypted,
    :certificate_subject,
    :not_before,
    :not_after,
    :fingerprint,
    :is_active
  ]

  @required_fields [:certificate_data_encrypted, :certificate_password_encrypted, :user_id]

  @doc "Builds a changeset for user certificate creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(user_certificate, attrs) do
    user_certificate
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id,
      name: :user_certificates_user_id_active_index,
      message: "already has an active certificate"
    )
  end
end
