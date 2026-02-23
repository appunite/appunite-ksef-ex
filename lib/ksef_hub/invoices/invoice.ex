defmodule KsefHub.Invoices.Invoice do
  @moduledoc "Invoice schema. Represents an income or expense invoice from KSeF or manual entry."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(income expense)
  @valid_statuses ~w(pending approved rejected)
  @valid_sources ~w(ksef manual)
  @valid_duplicate_statuses ~w(suspected confirmed dismissed)

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
    field :source, :string, default: "ksef"
    field :duplicate_status, :string
    field :ksef_acquisition_date, :utc_datetime_usec
    field :permanent_storage_date, :utc_datetime_usec

    belongs_to :company, KsefHub.Companies.Company
    belongs_to :duplicate_of, __MODULE__
    has_many :duplicates, __MODULE__, foreign_key: :duplicate_of_id
    belongs_to :category, KsefHub.Invoices.Category
    has_many :invoice_tags, KsefHub.Invoices.InvoiceTag
    many_to_many :tags, KsefHub.Invoices.Tag, join_through: KsefHub.Invoices.InvoiceTag

    timestamps()
  end

  @doc "Builds a changeset for invoice creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
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
      :source,
      :duplicate_of_id,
      :duplicate_status,
      :ksef_acquisition_date,
      :permanent_storage_date,
      :category_id
    ])
    |> validate_required([
      :type,
      :seller_nip,
      :seller_name,
      :invoice_number,
      :issue_date,
      :company_id
    ])
    |> validate_format(:seller_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> validate_format(:buyer_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_source_requirements()
    |> validate_duplicate_status()
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:duplicate_of_id)
    |> foreign_key_constraint(:category_id)
    |> unique_constraint([:company_id, :ksef_number],
      name: :invoices_company_id_ksef_number_unique_non_duplicate
    )
  end

  @doc "Builds a changeset for updating duplicate fields only."
  @spec duplicate_changeset(t(), map()) :: Ecto.Changeset.t()
  def duplicate_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:duplicate_of_id, :duplicate_status])
    |> validate_duplicate_status()
    |> foreign_key_constraint(:duplicate_of_id)
  end

  @doc "Builds a changeset for assigning or clearing a category."
  @spec category_changeset(t(), map()) :: Ecto.Changeset.t()
  def category_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:category_id])
    |> foreign_key_constraint(:category_id)
  end

  @spec validate_source_requirements(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_source_requirements(changeset) do
    source = get_field(changeset, :source)

    case source do
      "ksef" ->
        validate_required(changeset, [:xml_content])

      "manual" ->
        validate_required(changeset, [:buyer_nip, :buyer_name, :net_amount, :gross_amount])

      _ ->
        changeset
    end
  end

  @spec validate_duplicate_status(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_duplicate_status(changeset) do
    duplicate_status = get_field(changeset, :duplicate_status)

    if duplicate_status do
      validate_inclusion(changeset, :duplicate_status, @valid_duplicate_statuses)
    else
      changeset
    end
  end
end
