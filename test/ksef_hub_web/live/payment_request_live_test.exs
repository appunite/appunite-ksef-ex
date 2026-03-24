defmodule KsefHubWeb.PaymentRequestLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, owner} =
      Accounts.get_or_create_google_user(%{
        uid: "g-pr-owner",
        email: "pr-owner@example.com",
        name: "PR Owner"
      })

    company = insert(:company, name: "PR Corp")
    insert(:membership, user: owner, company: company, role: :owner)
    conn = log_in_user(conn, owner, %{current_company_id: company.id})
    %{conn: conn, owner: owner, company: company}
  end

  describe "Index" do
    test "renders payment requests list", %{conn: conn, company: company, owner: owner} do
      insert(:payment_request,
        company: company,
        created_by: owner,
        recipient_name: "Acme Sp. z o.o."
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests")
      assert has_element?(view, "h1", "Payment Requests")
      assert has_element?(view, "td", "Acme Sp. z o.o.")
    end

    test "filters by status", %{conn: conn, company: company, owner: owner} do
      insert(:payment_request,
        company: company,
        created_by: owner,
        status: :pending,
        recipient_name: "Pending Co"
      )

      insert(:payment_request,
        company: company,
        created_by: owner,
        status: :paid,
        recipient_name: "Paid Co"
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests?status=paid")
      assert has_element?(view, "td", "Paid Co")
      refute has_element?(view, "td", "Pending Co")
    end

    test "searches by query", %{conn: conn, company: company, owner: owner} do
      insert(:payment_request,
        company: company,
        created_by: owner,
        recipient_name: "Unique Vendor"
      )

      insert(:payment_request,
        company: company,
        created_by: owner,
        recipient_name: "Other Corp"
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests?query=Unique")
      assert has_element?(view, "td", "Unique Vendor")
      refute has_element?(view, "td", "Other Corp")
    end

    test "bulk mark as paid", %{conn: conn, company: company, owner: owner} do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :pending,
          recipient_name: "To Pay"
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests")

      # Select the payment request
      render_click(view, "toggle_select", %{"id" => pr.id})

      # Mark as paid
      render_click(view, "mark_paid", %{})

      # Should show flash
      assert render(view) =~ "marked as paid"
    end

    test "shows selected totals grouped by currency", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr1 =
        insert(:payment_request,
          company: company,
          created_by: owner,
          amount: Decimal.new("100.50"),
          currency: "PLN"
        )

      pr2 =
        insert(:payment_request,
          company: company,
          created_by: owner,
          amount: Decimal.new("200.00"),
          currency: "PLN"
        )

      pr3 =
        insert(:payment_request,
          company: company,
          created_by: owner,
          amount: Decimal.new("340.00"),
          currency: "EUR"
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests")

      # Select all three
      render_click(view, "toggle_select", %{"id" => pr1.id})
      render_click(view, "toggle_select", %{"id" => pr2.id})
      render_click(view, "toggle_select", %{"id" => pr3.id})

      html = render(view)
      assert html =~ "3 selected"
      assert html =~ "340.00"
      assert html =~ "EUR"
      assert html =~ "300.50"
      assert html =~ "PLN"
    end

    test "voided payment request has no checkbox", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :voided,
          recipient_name: "Voided Co"
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests")
      assert has_element?(view, "td", "Voided Co")
      refute has_element?(view, "#pr-#{pr.id} input[type='checkbox']")
    end

    test "shows empty state", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/payment-requests")
      assert html =~ "No payment requests found"
    end

    test "accountant can view payment requests", %{company: company} do
      {:ok, accountant} =
        Accounts.get_or_create_google_user(%{
          uid: "g-pr-accountant",
          email: "pr-acc@example.com",
          name: "Accountant"
        })

      insert(:membership, user: accountant, company: company, role: :accountant)

      conn =
        build_conn()
        |> log_in_user(accountant, %{current_company_id: company.id})

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests")
      assert has_element?(view, "h1", "Payment Requests")
      # Accountant should not see the "New payment request" button (can't manage)
      refute has_element?(view, "a", "New payment request")
    end
  end

  describe "Form" do
    test "renders new payment request form", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/new")
      assert has_element?(view, "h1", "New Payment Request")
    end

    test "pre-fills from invoice", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          type: :expense,
          seller_name: "Invoice Seller",
          gross_amount: Decimal.new("5000.00"),
          currency: "PLN",
          invoice_number: "FV/2026/99"
        )

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/payment-requests/new?invoice_id=#{invoice.id}")

      assert has_element?(view, "[data-testid='linked-invoice']")
      html = render(view)
      assert html =~ "Invoice Seller"
      assert html =~ "FV/2026/99"
    end

    test "creates payment request on submit", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/new")

      view
      |> form("form[phx-submit='save']", %{
        "payment_request" => %{
          "recipient_name" => "New Recipient",
          "amount" => "999.99",
          "currency" => "PLN",
          "title" => "Test Payment",
          "iban" => "PL61109010140000071219812874"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/c/#{company.id}/payment-requests")
    end

    test "validates form on change", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/new")

      html =
        render_change(view, "validate", %{
          "payment_request" => %{
            "recipient_name" => "",
            "amount" => "",
            "currency" => "",
            "title" => "",
            "iban" => ""
          }
        })

      assert html =~ "blank"
    end

    test "edits an existing payment request", %{conn: conn, company: company, owner: owner} do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          recipient_name: "Old Name",
          title: "Old Title"
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")
      assert has_element?(view, "h1", "Edit Payment Request")

      view
      |> form("form[phx-submit='save']", %{
        "payment_request" => %{
          "recipient_name" => "Updated Name",
          "title" => "Updated Title"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/c/#{company.id}/payment-requests")

      updated = KsefHub.PaymentRequests.get_payment_request!(company.id, pr.id)
      assert updated.recipient_name == "Updated Name"
      assert updated.title == "Updated Title"
      assert updated.updated_by_id == owner.id
    end

    test "shows audit info on edit page", %{conn: conn, company: company, owner: owner} do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          recipient_name: "Audit Test"
        )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")
      assert html =~ "Created by"
      assert html =~ owner.name
    end

    test "shows void button for pending payment request", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :pending
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")
      assert has_element?(view, "button", "Void")
    end

    test "void action voids the payment request", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :pending
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")
      render_click(view, "void", %{})

      assert_redirect(view, ~p"/c/#{company.id}/payment-requests")

      updated = KsefHub.PaymentRequests.get_payment_request!(company.id, pr.id)
      assert updated.status == :voided
    end

    test "shows voided payment request as read-only", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :voided
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")
      assert has_element?(view, "[data-testid='voided-banner']")
      refute has_element?(view, "button", "Save changes")
      refute has_element?(view, "button", "Void")
      assert render(view) =~ "Back"
    end

    test "shows paid payment request as read-only", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :paid
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")
      assert has_element?(view, "[data-testid='paid-banner']")
      assert has_element?(view, "h1", "Payment Request")
      refute has_element?(view, "button", "Save changes")
      assert render(view) =~ "Back"
    end

    test "server-side rejects save on paid payment request", %{
      conn: conn,
      company: company,
      owner: owner
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: owner,
          status: :paid
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/payment-requests/#{pr.id}/edit")

      render_submit(view, "save", %{
        "payment_request" => %{"title" => "Hacked Title"}
      })

      {path, flash} = assert_redirect(view)
      assert path == "/c/#{company.id}/payment-requests"
      assert flash["error"] =~ "Only pending"
    end

    test "handles invalid invoice_id gracefully", %{conn: conn, company: company} do
      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/payment-requests/new?invoice_id=#{Ecto.UUID.generate()}")

      refute has_element?(view, "[data-testid='linked-invoice']")
    end
  end
end
