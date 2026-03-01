defmodule KsefHub.InboundEmail.InboundEmail do
  @moduledoc "Schema for inbound email audit log. Tracks received emails and their processing status."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type status :: :received | :processing | :completed | :failed | :rejected

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inbound_emails" do
    field :mailgun_message_id, :string
    field :sender, :string
    field :recipient, :string
    field :subject, :string
    field :status, Ecto.Enum, values: [:received, :processing, :completed, :failed, :rejected]
    field :error_message, :string
    field :original_filename, :string

    belongs_to :company, KsefHub.Companies.Company
    belongs_to :invoice, KsefHub.Invoices.Invoice
    belongs_to :pdf_file, KsefHub.Files.File

    timestamps()
  end

  @doc "Builds a changeset for creating an inbound email record."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(inbound_email, attrs) do
    inbound_email
    |> cast(attrs, [
      :company_id,
      :mailgun_message_id,
      :sender,
      :recipient,
      :subject,
      :status,
      :error_message,
      :original_filename,
      :pdf_file_id
    ])
    |> validate_required([:company_id, :sender, :recipient, :status])
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:pdf_file_id)
    |> unique_constraint(:mailgun_message_id, name: :inbound_emails_mailgun_message_id_index)
  end

  @doc "Builds a changeset for updating status and related fields."
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(inbound_email, attrs) do
    inbound_email
    |> cast(attrs, [:status, :error_message, :invoice_id])
    |> validate_required([:status])
    |> foreign_key_constraint(:invoice_id)
  end
end
