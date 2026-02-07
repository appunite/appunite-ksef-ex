defmodule KsefHub.Invoices.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(income expense)
  @valid_statuses ~w(pending approved rejected)

  schema "invoices" do
    field :ksef_number, :string
    field :type, :string
    field :xml_content, :string
    field :seller_nip, :string
    field :seller_name, :string
    field :buyer_nip, :string
    field :buyer_name, :string
    field :invoice_number, :string
    field :issue_date, :date
    field :net_amount, :decimal
    field :vat_amount, :decimal
    field :gross_amount, :decimal
    field :currency, :string, default: "PLN"
    field :status, :string, default: "pending"
    field :ksef_acquisition_date, :utc_datetime_usec
    field :permanent_storage_date, :utc_datetime_usec

    timestamps()
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :ksef_number,
      :type,
      :xml_content,
      :seller_nip,
      :seller_name,
      :buyer_nip,
      :buyer_name,
      :invoice_number,
      :issue_date,
      :net_amount,
      :vat_amount,
      :gross_amount,
      :currency,
      :status,
      :ksef_acquisition_date,
      :permanent_storage_date
    ])
    |> validate_required([:type, :seller_nip, :seller_name, :invoice_number, :issue_date])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:ksef_number)
  end
end
