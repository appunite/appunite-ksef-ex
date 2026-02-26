defmodule KsefHub.Repo.Migrations.CreateInboundEmails do
  use Ecto.Migration

  def change do
    create table(:inbound_emails, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :nilify_all)
      add :mailgun_message_id, :string
      add :sender, :string, null: false
      add :recipient, :string, null: false
      add :subject, :string
      add :status, :string, null: false, default: "received"
      add :error_message, :text
      add :pdf_content, :binary
      add :original_filename, :string

      timestamps()
    end

    create index(:inbound_emails, [:company_id])
    create index(:inbound_emails, [:invoice_id])

    create unique_index(:inbound_emails, [:mailgun_message_id],
             where: "mailgun_message_id IS NOT NULL"
           )
  end
end
