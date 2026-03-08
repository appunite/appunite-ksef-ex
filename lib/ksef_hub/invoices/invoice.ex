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
    field :note, :string
    field :purchase_order, :string
    field :sales_date, :date
    field :due_date, :date
    field :iban, :string
    field :seller_address, :map
    field :buyer_address, :map

    belongs_to :company, KsefHub.Companies.Company
    belongs_to :duplicate_of, __MODULE__
    has_many :duplicates, __MODULE__, foreign_key: :duplicate_of_id
    belongs_to :category, KsefHub.Invoices.Category
    belongs_to :xml_file, KsefHub.Files.File
    belongs_to :pdf_file, KsefHub.Files.File
    has_many :invoice_tags, KsefHub.Invoices.InvoiceTag
    many_to_many :tags, KsefHub.Invoices.Tag, join_through: KsefHub.Invoices.InvoiceTag
    has_many :comments, KsefHub.Invoices.InvoiceComment
    belongs_to :created_by, KsefHub.Accounts.User
    has_one :inbound_email, KsefHub.InboundEmail.InboundEmail

    field :public_token, :string

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

  @address_field_atoms ~w(street city postal_code country)a
  @address_field_strings Enum.map(@address_field_atoms, &Atom.to_string/1)

  @doc "Formats an address map as a comma-separated string. Handles both atom and string keys (JSONB round-trip returns strings)."
  @spec format_address(map() | nil) :: String.t()
  def format_address(nil), do: ""

  def format_address(addr) when is_map(addr) do
    Enum.zip(@address_field_atoms, @address_field_strings)
    |> Enum.map(fn {atom_key, str_key} -> addr[atom_key] || addr[str_key] end)
    |> Enum.reject(&blank_value?/1)
    |> Enum.map_join(", ", &String.trim/1)
  end

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
      :gross_amount,
      :currency,
      :status,
      :source,
      :duplicate_of_id,
      :duplicate_status,
      :ksef_acquisition_date,
      :permanent_storage_date,
      :extraction_status,
      :original_filename,
      :purchase_order,
      :sales_date,
      :due_date,
      :iban,
      :seller_address,
      :buyer_address,
      :created_by_id
    ])
    |> validate_required([:type, :company_id])
    |> validate_nip_fields()
    |> validate_length(:original_filename, max: 255)
    |> validate_length(:purchase_order, max: 256)
    |> validate_length(:iban, min: 15, max: 34)
    |> normalize_address_fields()
    |> validate_source_requirements()
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:duplicate_of_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:xml_file_id)
    |> foreign_key_constraint(:pdf_file_id)
    |> unique_constraint([:company_id, :ksef_number],
      name: :invoices_company_id_ksef_number_unique_non_duplicate
    )
  end

  @doc "Builds a changeset that generates a cryptographically random public sharing token."
  @spec public_token_changeset(t()) :: Ecto.Changeset.t()
  def public_token_changeset(invoice) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    invoice
    |> change(%{public_token: token})
    |> unique_constraint(:public_token)
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

  @all_edit_fields [
    :invoice_number,
    :issue_date,
    :sales_date,
    :due_date,
    :seller_nip,
    :seller_name,
    :buyer_nip,
    :buyer_name,
    :net_amount,
    :gross_amount,
    :currency,
    :purchase_order,
    :iban,
    :seller_address,
    :buyer_address
  ]

  @doc "Builds a changeset for manual field edits on the show page. Excludes company-side fields based on invoice type."
  @spec edit_changeset(t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, editable_fields(invoice.type))
    |> validate_nip_fields()
    |> validate_number(:net_amount, greater_than_or_equal_to: 0)
    |> validate_number(:gross_amount, greater_than_or_equal_to: 0)
    |> validate_length(:purchase_order, max: 256)
    |> validate_length(:iban, min: 15, max: 34)
    |> normalize_address_fields()
  end

  @doc "Returns the company-owned fields that should not be user-editable for a given invoice type."
  @spec company_fields(invoice_type()) :: [atom()]
  def company_fields(:expense), do: [:buyer_nip, :buyer_name]
  def company_fields(:income), do: [:seller_nip, :seller_name]
  def company_fields(_), do: []

  @doc "Returns the fields that are editable for a given invoice type (excludes company-owned fields)."
  @spec editable_fields(invoice_type() | nil) :: [atom()]
  def editable_fields(type), do: @all_edit_fields -- company_fields(type)

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

  @doc "Builds a changeset for updating the note field only."
  @spec note_changeset(t(), map()) :: Ecto.Changeset.t()
  def note_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:note])
    |> validate_length(:note, max: 5000)
  end

  @spec validate_nip_fields(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_nip_fields(changeset) do
    case get_field(changeset, :source) do
      :ksef ->
        changeset
        |> validate_format(:seller_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")
        |> validate_format(:buyer_nip, ~r/^\d{10}$/, message: "must be a 10-digit NIP")

      _ ->
        changeset
        |> validate_length(:seller_nip, max: 50)
        |> validate_length(:buyer_nip, max: 50)
    end
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

  @spec normalize_address_fields(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_address_fields(changeset) do
    Enum.reduce([:seller_address, :buyer_address], changeset, &maybe_nil_blank_address/2)
  end

  @spec maybe_nil_blank_address(atom(), Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp maybe_nil_blank_address(field, changeset) do
    case get_change(changeset, field) do
      %{} = addr ->
        if address_blank?(addr), do: put_change(changeset, field, nil), else: changeset

      _ ->
        changeset
    end
  end

  @spec address_blank?(map()) :: boolean()
  defp address_blank?(addr) do
    addr |> Map.values() |> Enum.all?(&blank_value?/1)
  end

  @spec blank_value?(term()) :: boolean()
  defp blank_value?(nil), do: true
  defp blank_value?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank_value?(_), do: false
end
