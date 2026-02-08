defmodule KsefHub.CompaniesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Companies
  alias KsefHub.Companies.Company

  describe "create_company/1" do
    test "creates a company with valid attributes" do
      attrs = %{name: "Acme Sp. z o.o.", nip: "1234567890"}
      assert {:ok, %Company{} = company} = Companies.create_company(attrs)
      assert company.name == "Acme Sp. z o.o."
      assert company.nip == "1234567890"
      assert company.is_active == true
    end

    test "creates a company with address" do
      attrs = %{name: "Acme", nip: "1234567890", address: "ul. Testowa 1, Warszawa"}
      assert {:ok, %Company{} = company} = Companies.create_company(attrs)
      assert company.address == "ul. Testowa 1, Warszawa"
    end

    test "requires name" do
      assert {:error, changeset} = Companies.create_company(%{nip: "1234567890"})
      assert errors_on(changeset).name
    end

    test "requires NIP" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme"})
      assert errors_on(changeset).nip
    end

    test "rejects NIP that is too short" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme", nip: "12345"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "rejects NIP that is too long" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme", nip: "12345678901"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "rejects NIP with non-digit characters" do
      assert {:error, changeset} = Companies.create_company(%{name: "Acme", nip: "123456789a"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "enforces unique NIP" do
      insert(:company, nip: "1234567890")
      assert {:error, changeset} = Companies.create_company(%{name: "Other", nip: "1234567890"})
      assert "has already been taken" in errors_on(changeset).nip
    end
  end

  describe "list_companies/0" do
    test "returns all active companies ordered by name" do
      insert(:company, name: "Company A")
      insert(:company, name: "Company B")
      insert(:company, name: "Company C", is_active: false)

      companies = Companies.list_companies()
      assert length(companies) == 2
      assert [%{name: "Company A"}, %{name: "Company B"}] = companies
    end

    test "returns empty list when no companies" do
      assert Companies.list_companies() == []
    end
  end

  describe "get_company!/1" do
    test "returns the company with the given id" do
      company = insert(:company)
      assert Companies.get_company!(company.id).id == company.id
    end

    test "raises when company not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Companies.get_company!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_company/1" do
    test "returns the company with the given id" do
      company = insert(:company)
      assert %Company{} = Companies.get_company(company.id)
    end

    test "returns nil when company not found" do
      assert Companies.get_company(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_company/2" do
    test "updates the company name" do
      company = insert(:company)
      assert {:ok, updated} = Companies.update_company(company, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "does not allow changing NIP to invalid" do
      company = insert(:company)
      assert {:error, changeset} = Companies.update_company(company, %{nip: "bad"})
      assert "must be a 10-digit NIP" in errors_on(changeset).nip
    end

    test "enforces unique NIP on update" do
      insert(:company, nip: "1111111111")
      company = insert(:company, nip: "2222222222")
      assert {:error, changeset} = Companies.update_company(company, %{nip: "1111111111"})
      assert "has already been taken" in errors_on(changeset).nip
    end
  end
end
