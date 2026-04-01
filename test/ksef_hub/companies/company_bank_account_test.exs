defmodule KsefHub.Companies.CompanyBankAccountTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Companies
  alias KsefHub.Companies.CompanyBankAccount

  describe "changeset/2" do
    test "valid changeset" do
      changeset =
        CompanyBankAccount.changeset(%CompanyBankAccount{}, %{
          currency: "PLN",
          iban: "PL12105015201000009032123698",
          label: "Main PLN"
        })

      assert changeset.valid?
    end

    test "requires currency and iban" do
      changeset = CompanyBankAccount.changeset(%CompanyBankAccount{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).currency
      assert errors_on(changeset).iban
    end

    test "validates currency format (3-letter uppercase)" do
      changeset =
        CompanyBankAccount.changeset(%CompanyBankAccount{}, %{
          currency: "pln",
          iban: "PL12105015201000009032123698"
        })

      refute changeset.valid?
      assert errors_on(changeset).currency
    end

    test "validates IBAN length" do
      changeset =
        CompanyBankAccount.changeset(%CompanyBankAccount{}, %{
          currency: "PLN",
          iban: "PL123"
        })

      refute changeset.valid?
      assert errors_on(changeset).iban
    end
  end

  describe "context CRUD" do
    setup do
      company = insert(:company)
      %{company: company}
    end

    test "create and list bank accounts", %{company: company} do
      {:ok, ba} =
        Companies.create_bank_account(company.id, %{
          currency: "PLN",
          iban: "PL12105015201000009032123698"
        })

      assert ba.currency == "PLN"
      assert [found] = Companies.list_bank_accounts(company.id)
      assert found.id == ba.id
    end

    test "get_bank_account_for_currency returns matching account", %{company: company} do
      insert(:company_bank_account, company: company, currency: "PLN")

      assert %CompanyBankAccount{currency: "PLN"} =
               Companies.get_bank_account_for_currency(company.id, "PLN")
    end

    test "get_bank_account_for_currency returns nil when not found", %{company: company} do
      assert nil == Companies.get_bank_account_for_currency(company.id, "EUR")
    end

    test "enforces unique constraint on company + currency", %{company: company} do
      insert(:company_bank_account, company: company, currency: "PLN")

      assert {:error, changeset} =
               Companies.create_bank_account(company.id, %{
                 currency: "PLN",
                 iban: "PL99999999999999999999999999"
               })

      assert "a bank account for this currency already exists" in errors_on(changeset).currency
    end

    test "update bank account", %{company: company} do
      ba = insert(:company_bank_account, company: company)
      {:ok, updated} = Companies.update_bank_account(ba, %{label: "Updated"})
      assert updated.label == "Updated"
    end

    test "delete bank account", %{company: company} do
      ba = insert(:company_bank_account, company: company)
      {:ok, _} = Companies.delete_bank_account(ba)
      assert [] == Companies.list_bank_accounts(company.id)
    end
  end
end
