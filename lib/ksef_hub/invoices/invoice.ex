defmodule KsefHub.Invoices.Invoice do
  @moduledoc "Invoice schema. Represents an income or expense invoice from KSeF or manual entry."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type invoice_type :: :income | :expense
  @type invoice_status :: :pending | :approved | :rejected
  @type invoice_source :: :ksef | :manual | :pdf_upload | :email
  @type extraction_status :: :complete | :partial | :failed
  @type duplicate_status :: :suspected | :confirmed | :dismissed
  @type prediction_status :: :pending | :predicted | :needs_review | :manual

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoices" do
    field :ksef_number, :string
    field :type, Ecto.Enum, values: [:income, :expense]
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
    field :status, Ecto.Enum, values: [:pending, :approved, :rejected], default: :pending
    field :source, Ecto.Enum, values: [:ksef, :manual, :pdf_upload, :email], default: :ksef
    field :duplicate_status, Ecto.Enum, values: [:suspected, :confirmed, :dismissed]
    field :ksef_acquisition_date, :utc_datetime_usec
    field :permanent_storage_date, :utc_datetime_usec

    field :prediction_status, Ecto.Enum, values: [:pending, :predicted, :needs_review, :manual]
    field :prediction_category_name, :string
    field :prediction_tag_name, :string
    field :prediction_category_confidence, :float
    field :prediction_tag_confidence, :float
    field :prediction_model_version, :string
    field :prediction_category_probabilities, :map
    field :prediction_tag_probabilities, :map
    field :prediction_predicted_at, :utc_datetime_usec

    field :extraction_status, Ecto.Enum, values: [:complete, :partial, :failed]
    field :original_filename, :string

    belongs_to :company, KsefHub.Companies.Company
    belongs_to :duplicate_of, __MODULE__
    has_many :duplicates, __MODULE__, foreign_key: :duplicate_of_id
    belongs_to :category, KsefHub.Invoices.Category
    belongs_to :xml_file, KsefHub.Files.File
    belongs_to :pdf_file, KsefHub.Files.File
    has_many :invoice_tags, KsefHub.Invoices.InvoiceTag
    many_to_many :tags, KsefHub.Invoices.Tag, join_through: KsefHub.Invoices.InvoiceTag

    timestamps()
  end

  @doc "Returns the list of valid invoice types."
  @spec types() :: [invoice_type()]
  def types, do: Ecto.Enum.values(__MODULE__, :type)

  @doc "Returns the list of valid invoice statuses."
  @spec statuses() :: [invoice_status()]
  def statuses, do: Ecto.Enum.values(__MODULE__, :status)

  @doc "Returns the list of valid invoice sources."
  @spec sources() :: [invoice_source()]
  def sources, do: Ecto.Enum.values(__MODULE__, :source)

  @doc "Builds a changeset for invoice creation/update."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :ksef_number,
      :type,
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
      :extraction_status,
      :original_filename
    ])
    |> validate_required([:type, :company_id])
    |> validate_format(:seller_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> validate_format(:buyer_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> validate_length(:original_filename, max: 255)
    |> validate_source_requirements()
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:duplicate_of_id)
    |> foreign_key_constraint(:xml_file_id)
    |> foreign_key_constraint(:pdf_file_id)
    |> unique_constraint([:company_id, :ksef_number],
      name: :invoices_company_id_ksef_number_unique_non_duplicate
    )
  end

  @doc "Builds a changeset for updating duplicate fields only."
  @spec duplicate_changeset(t(), map()) :: Ecto.Changeset.t()
  def duplicate_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:duplicate_of_id, :duplicate_status])
    |> foreign_key_constraint(:duplicate_of_id)
  end

  @doc "Builds a changeset for assigning or clearing a category."
  @spec category_changeset(t(), map()) :: Ecto.Changeset.t()
  def category_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:category_id])
    |> foreign_key_constraint(:category_id)
  end

  @edit_fields [
    :invoice_number,
    :issue_date,
    :seller_nip,
    :seller_name,
    :buyer_nip,
    :buyer_name,
    :net_amount,
    :vat_amount,
    :gross_amount,
    :currency
  ]

  @doc "Builds a changeset for manual field edits on the show page."
  @spec edit_changeset(t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @edit_fields)
    |> validate_format(:seller_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> validate_format(:buyer_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
    |> validate_number(:net_amount, greater_than_or_equal_to: 0)
    |> validate_number(:vat_amount, greater_than_or_equal_to: 0)
    |> validate_number(:gross_amount, greater_than_or_equal_to: 0)
  end

  @prediction_fields [
    :prediction_status,
    :prediction_category_name,
    :prediction_tag_name,
    :prediction_category_confidence,
    :prediction_tag_confidence,
    :prediction_model_version,
    :prediction_category_probabilities,
    :prediction_tag_probabilities,
    :prediction_predicted_at
  ]

  @doc "Builds a changeset for updating ML prediction fields."
  @spec prediction_changeset(t(), map()) :: Ecto.Changeset.t()
  def prediction_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @prediction_fields)
  end

  @spec validate_source_requirements(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_source_requirements(changeset) do
    source = get_field(changeset, :source)

    case source do
      :ksef ->
        validate_required(changeset, [
          :xml_file_id,
          :seller_nip,
          :seller_name,
          :invoice_number,
          :issue_date
        ])

      :manual ->
        validate_required(changeset, [
          :seller_nip,
          :seller_name,
          :invoice_number,
          :issue_date,
          :buyer_nip,
          :buyer_name,
          :net_amount,
          :gross_amount
        ])

      source when source in [:pdf_upload, :email] ->
        validate_required(changeset, [:pdf_file_id, :extraction_status])

      _ ->
        changeset
    end
  end
end
