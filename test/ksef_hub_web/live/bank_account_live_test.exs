defmodule KsefHubWeb.BankAccountLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-ba-owner",
        email: "ba-owner@example.com",
        name: "BA Owner"
      })

    company = insert(:company, name: "BA Corp")
    insert(:membership, user: user, company: company, role: :owner)
    conn = log_in_user(conn, user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "index" do
    test "renders bank accounts page", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")
      assert html =~ "Bank Accounts"
      assert html =~ "No bank accounts configured"
    end

    test "lists existing bank accounts", %{conn: conn, company: company} do
      insert(:company_bank_account,
        company: company,
        currency: "PLN",
        iban: "PL12105015201000009032123698"
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")
      assert html =~ "PLN"
      assert html =~ "PL12105015201000009032123698"
    end

    test "creates a new bank account", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")

      view |> element("button", "Add Account") |> render_click()
      assert render(view) =~ "New Bank Account"

      view
      |> form("form[phx-submit='save']",
        bank_account: %{currency: "EUR", iban: "DE89370400440532013000"}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "EUR"
      assert html =~ "DE89370400440532013000"
      assert html =~ "Bank account for EUR created."
    end

    test "validates form on change", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")

      view |> element("button", "Add Account") |> render_click()

      html =
        view
        |> form("form[phx-submit='save']", bank_account: %{currency: "bad", iban: "short"})
        |> render_change()

      assert html =~ "must be a 3-letter uppercase code"
    end

    test "edits a bank account", %{conn: conn, company: company} do
      ba = insert(:company_bank_account, company: company, currency: "PLN")
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")

      view |> element("button[phx-value-id='#{ba.id}']", "Edit") |> render_click()
      assert render(view) =~ "Edit Bank Account"

      view
      |> form("form[phx-submit='save']",
        bank_account: %{iban: "PL99999999999999999999999999", label: "Updated"}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "PL99999999999999999999999999"
      assert html =~ "Bank account for PLN updated."
    end

    test "deletes a bank account", %{conn: conn, company: company} do
      ba = insert(:company_bank_account, company: company, currency: "PLN")
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")

      view |> element("button[phx-value-id='#{ba.id}']", "Delete") |> render_click()

      html = render(view)
      assert html =~ "Bank account for PLN deleted."
    end

    test "cancels form", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/bank-accounts")

      view |> element("button", "Add Account") |> render_click()
      assert render(view) =~ "New Bank Account"

      view |> element("button", "Cancel") |> render_click()
      refute render(view) =~ "New Bank Account"
    end

    test "accountant cannot access bank accounts", %{company: company} do
      {:ok, accountant} =
        Accounts.get_or_create_google_user(%{
          uid: "g-ba-accountant",
          email: "ba-acc@example.com",
          name: "Accountant"
        })

      insert(:membership, user: accountant, company: company, role: :accountant)

      conn =
        build_conn()
        |> log_in_user(accountant, %{current_company_id: company.id})

      {:error, {:redirect, %{flash: flash}}} =
        live(conn, ~p"/c/#{company.id}/settings/bank-accounts")

      assert flash["error"] =~ "permission"
    end
  end
end
