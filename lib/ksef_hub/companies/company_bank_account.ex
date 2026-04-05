defmodule KsefHub.Companies.CompanyBankAccount do
  @moduledoc "Bank account for a company, keyed by currency. Used as the orderer account in payment CSV exports."

  use Ecto.Schema
  import Ecto.Changeset

  @behaviour KsefHub.ActivityLog.Trackable

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

  @doc "Builds a changeset for creating a company bank account."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(bank_account, attrs) do
    bank_account
    |> cast(attrs, [:currency, :iban, :label])
    |> common_validations()
  end

  @doc "Builds a changeset for updating a company bank account. Currency is immutable."
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(bank_account, attrs) do
    bank_account
    |> cast(attrs, [:iban, :label])
    |> common_validations()
  end

  @spec common_validations(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp common_validations(changeset) do
    changeset
    |> validate_required([:currency, :iban])
    |> validate_format(:currency, ~r/^[A-Z]{3}$/, message: "must be a 3-letter uppercase code")
    |> validate_length(:iban, min: 15, max: 34)
    |> validate_length(:label, max: 256)
    |> unique_constraint(:currency,
      name: :company_bank_accounts_company_id_currency_index,
      message: "a bank account for this currency already exists"
    )
    |> foreign_key_constraint(:company_id)
    |> check_constraint(:currency,
      name: :company_bank_accounts_currency_check,
      message: "must be a 3-letter uppercase code"
    )
    |> check_constraint(:iban,
      name: :company_bank_accounts_iban_check,
      message: "must be 15-34 alphanumeric characters"
    )
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_change(Ecto.Changeset.t()) :: {String.t(), map()}
  def track_change(%Ecto.Changeset{action: :insert} = cs) do
    {"bank_account.created",
     %{label: get_change(cs, :label), currency: get_change(cs, :currency)}}
  end

  def track_change(%Ecto.Changeset{} = cs) do
    {"bank_account.updated", %{label: cs.data.label || get_change(cs, :label)}}
  end

  @impl KsefHub.ActivityLog.Trackable
  @spec track_delete(t()) :: {String.t(), map()}
  def track_delete(account) do
    {"bank_account.deleted", %{label: account.label, currency: account.currency}}
  end
end
