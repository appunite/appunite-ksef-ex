defmodule KsefHub.PaymentRequests.PaymentRequest do
  @moduledoc "Payment request schema. Represents a wire transfer instruction for an invoice payment."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type status :: :pending | :paid | :voided

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @address_field_atoms ~w(street city postal_code country)a
  @address_field_strings Enum.map(@address_field_atoms, &Atom.to_string/1)

  schema "payment_requests" do
    field :recipient_name, :string
    field :recipient_address, :map
    field :amount, :decimal
    field :currency, :string, default: "PLN"
    field :title, :string
    field :iban, :string
    field :recipient_nip, :string
    field :note, :string
    field :paid_at, :utc_datetime_usec
    field :voided_at, :utc_datetime_usec
    field :status, Ecto.Enum, values: [:pending, :paid, :voided], default: :pending

    belongs_to :invoice, KsefHub.Invoices.Invoice
    belongs_to :company, KsefHub.Companies.Company
    belongs_to :created_by, KsefHub.Accounts.User
    belongs_to :updated_by, KsefHub.Accounts.User

    timestamps()
  end

  @doc "Returns the list of valid statuses."
  @spec statuses() :: [status()]
  def statuses, do: Ecto.Enum.values(__MODULE__, :status)

  @doc "Builds a changeset for creating or updating a payment request."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(payment_request, attrs) do
    payment_request
    |> cast(attrs, [
      :recipient_name,
      :recipient_nip,
      :recipient_address,
      :amount,
      :currency,
      :title,
      :iban,
      :note,
      :invoice_id,
      :company_id,
      :created_by_id,
      :updated_by_id
    ])
    |> validate_required([:recipient_name, :title, :iban, :amount, :currency])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:iban, min: 15, max: 34)
    |> validate_length(:recipient_name, max: 256)
    |> validate_length(:recipient_nip, max: 50)
    |> validate_length(:title, max: 256)
    |> normalize_address()
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:updated_by_id)
  end

  @doc "Builds a changeset that marks a payment request as paid."
  @spec mark_paid_changeset(t()) :: Ecto.Changeset.t()
  def mark_paid_changeset(payment_request) do
    change(payment_request, status: :paid, paid_at: DateTime.utc_now())
  end

  @doc "Builds a changeset that voids a payment request."
  @spec void_changeset(t()) :: Ecto.Changeset.t()
  def void_changeset(payment_request) do
    change(payment_request, status: :voided, voided_at: DateTime.utc_now())
  end

  @doc "Formats an address map as a comma-separated string. Delegates to Invoice.format_address/1."
  @spec format_address(map() | nil) :: String.t()
  defdelegate format_address(addr), to: KsefHub.Invoices.Invoice

  @spec normalize_address(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_address(changeset) do
    case get_change(changeset, :recipient_address) do
      nil ->
        changeset

      addr when is_map(addr) ->
        normalized =
          for {atom_key, str_key} <- Enum.zip(@address_field_atoms, @address_field_strings),
              into: %{} do
            value = addr[atom_key] || addr[str_key]
            {atom_key, if(blank_value?(value), do: nil, else: String.trim(value))}
          end

        if Enum.all?(Map.values(normalized), &is_nil/1) do
          put_change(changeset, :recipient_address, nil)
        else
          put_change(changeset, :recipient_address, normalized)
        end

      _ ->
        changeset
    end
  end

  @spec blank_value?(term()) :: boolean()
  defp blank_value?(nil), do: true
  defp blank_value?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank_value?(_), do: false
end
