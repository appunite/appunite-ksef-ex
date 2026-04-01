defmodule KsefHub.Repo.Migrations.AddDbConstraints do
  @moduledoc "Adds DB-level size and check constraints for recipient_nip and company_bank_accounts."

  use Ecto.Migration

  @doc "Adds size constraint on recipient_nip and check constraints on company_bank_accounts."
  @spec change() :: term()
  def change do
    alter table(:payment_requests) do
      modify :recipient_nip, :string, size: 50
    end

    create constraint(:company_bank_accounts, :company_bank_accounts_currency_check,
             check: "currency ~ '^[A-Z]{3}$'"
           )

    create constraint(:company_bank_accounts, :company_bank_accounts_iban_check,
             check: "iban ~ '^[A-Z0-9]{15,34}$'"
           )
  end
end
