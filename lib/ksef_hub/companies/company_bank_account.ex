defmodule KsefHub.Companies.CompanyBankAccount do
  @moduledoc "Bank account for a company, keyed by currency. Used as the orderer account in payment CSV exports."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "company_bank_accounts" do
    field :currency, :string
    field :iban, :string
    field :label, :string

    belongs_to :company, KsefHub.Companies.Company

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a company bank account."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(bank_account, attrs) do
    bank_account
    |> cast(attrs, [:currency, :iban, :label])
    |> validate_required([:currency, :iban])
    |> validate_format(:currency, ~r/^[A-Z]{3}$/, message: "must be a 3-letter uppercase code")
    |> validate_length(:iban, min: 15, max: 34)
    |> validate_length(:label, max: 256)
    |> unique_constraint(:currency,
      name: :company_bank_accounts_company_id_currency_index,
      message: "a bank account for this currency already exists"
    )
    |> foreign_key_constraint(:company_id)
  end
end
