defmodule KsefHubWeb.InvoiceLive.ShowTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invoices

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-show-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  defp stub_pdf(_context) do
    stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
    :ok
  end

  describe "mount" do
    test "renders invoice detail page", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta ->
        {:ok, "<html>preview</html>"}
      end)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
      assert html =~ invoice.seller_name
      assert html =~ invoice.buyer_name
    end

    test "renders download dropdown with PDF and XML links", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      xml_file = insert(:file, content: xml, content_type: "application/xml")

      invoice =
        insert(:invoice, type: :income, xml_file: xml_file, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta ->
        {:ok, "<html>preview</html>"}
      end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/pdf"]))
      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/xml"]))
    end

    test "shows preview when xml_file is available", %{conn: conn, company: company} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      xml_file = insert(:file, content: xml, content_type: "application/xml")

      invoice =
        insert(:invoice, type: :income, xml_file: xml_file, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta ->
        {:ok, "<html>preview</html>"}
      end)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "preview"
    end
  end

  describe "approve/reject" do
    setup :stub_pdf

    test "approve button shown for pending expense invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "button", "Approve")
      assert has_element?(view, "button", "Reject")
    end

    test "approve button not shown for income invoices", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "button", "Approve")
    end

    test "clicking approve updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view |> element("button", "Approve") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "clicking reject updates status", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view |> element("button", "Reject") |> render_click()

      assert has_element?(view, "[class*=rounded-md]", "rejected")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end

    test "approve on income invoice is rejected", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Buttons aren't shown for income, but test the server-side guard via hook
      render_hook(view, "approve", %{})

      # Status should remain pending (not changed to approved)
      assert has_element?(view, "[class*=rounded-md]", "pending")
      refute has_element?(view, "[class*=rounded-md]", "approved")
    end

    test "already-approved invoice does not show action buttons", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, status: :approved, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, "[class*=rounded-md]", "approved")
      refute has_element?(view, "button", "Approve")
      refute has_element?(view, "button", "Reject")
    end
  end

  describe "category and tags display" do
    setup :stub_pdf

    test "displays category name and emoji", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "finance:invoices", emoji: "💰")
      invoice = insert(:invoice, company: company, category: category)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=category-select]")
      html = render(view)
      assert html =~ "finance:invoices"
      assert html =~ "💰"
    end

    test "displays assigned tags", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "quarterly-report")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "quarterly-report"
    end

    test "shows needs_review prediction indicator", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, prediction_status: :needs_review)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "needs review"
    end
  end

  describe "category editing" do
    setup :stub_pdf

    test "selecting a category updates the invoice", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "ops:hosting", emoji: "🖥")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> form("[data-testid=category-form]", %{"category_id" => category.id})
      |> render_change()

      html = render(view)
      assert html =~ "ops:hosting"

      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert updated.category_id == category.id
      assert updated.prediction_status == :manual
    end

    test "clearing category sets it to nil", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "ops:clear-test")
      invoice = insert(:invoice, company: company, category: category)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> form("[data-testid=category-form]", %{"category_id" => ""})
      |> render_change()

      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert is_nil(updated.category_id)
    end
  end

  describe "tag editing" do
    setup :stub_pdf

    test "toggling a tag on adds it to the invoice", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "toggle-on")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> element(~s(input[phx-value-tag-id="#{tag.id}"]))
      |> render_click()

      tags = Invoices.list_invoice_tags(invoice.id)
      assert Enum.any?(tags, &(&1.id == tag.id))
    end

    test "toggling a tag off removes it from the invoice", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "toggle-off")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> element(~s(input[phx-value-tag-id="#{tag.id}"]))
      |> render_click()

      tags = Invoices.list_invoice_tags(invoice.id)
      refute Enum.any?(tags, &(&1.id == tag.id))
    end

    test "creating a new tag inline adds it to the invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> element("form[phx-submit=create_and_add_tag]")
      |> render_submit(%{"name" => "brand-new-tag"})

      html = render(view)
      assert html =~ "brand-new-tag"

      tags = Invoices.list_invoice_tags(invoice.id)
      assert Enum.any?(tags, &(&1.name == "brand-new-tag"))
    end
  end

  describe "extraction status display" do
    test "shows extraction badge for partial invoice", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[class*=rounded-md]", "Incomplete")
      assert has_element?(view, ~s([data-testid="extraction-warning"]))
    end

    test "does not show extraction badge for complete invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, extraction_status: :complete)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "[class*=rounded-md]", "Incomplete")
      refute has_element?(view, ~s([data-testid="extraction-warning"]))
    end

    test "approve shows specific error for partial extraction invoice", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice,
          company: company,
          type: :expense,
          extraction_status: :partial,
          net_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      html = view |> element("button", "Approve") |> render_click()
      assert html =~ "extraction is incomplete"
    end
  end

  describe "edit form" do
    test "shows edit form when Edit button is clicked", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "form[phx-submit=save_edit]")

      view |> element("button", "Edit") |> render_click()
      assert has_element?(view, "form[phx-submit=save_edit]")
    end

    test "edit form opens automatically for partial extraction", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "form[phx-submit=save_edit]")
    end

    test "cancel edit returns to read-only view", %{conn: conn, company: company} do
      invoice =
        insert(:invoice, company: company, extraction_status: :partial, net_amount: nil)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "form[phx-submit=save_edit]")

      view |> element("button", "Cancel") |> render_click()
      refute has_element?(view, "form[phx-submit=save_edit]")
    end

    test "saving edit updates invoice and exits edit mode", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          extraction_status: :partial,
          net_amount: nil,
          gross_amount: nil
        )

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "net_amount" => "1000.00",
          "gross_amount" => "1230.00"
        }
      })
      |> render_submit()

      assert has_element?(view, "#flash-info", "Invoice updated")
      refute has_element?(view, "form[phx-submit=save_edit]")
      # extraction status should now be complete, no warning banner
      refute has_element?(view, ~s([data-testid="extraction-warning"]))
    end

    test "accepts foreign tax ID in seller_nip field", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{"seller_nip" => "FR61823475082"}
      })
      |> render_submit()

      # Form should be closed (edit successful)
      refute has_element?(view, "form[phx-submit=save_edit]")

      # Verify persistence
      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.seller_nip == "FR61823475082"
    end
  end

  describe "pdf_upload invoice" do
    setup :stub_pdf

    test "shows PDF preview iframe", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert html =~ ~s(src="/c/#{company.id}/invoices/#{invoice.id}/pdf?inline=1")
      assert html =~ "Invoice PDF preview"
    end

    test "shows download dropdown with PDF but not XML", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      assert has_element?(view, "div.dropdown")
      assert has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/pdf"]))
      refute has_element?(view, ~s(a[href="/c/#{company.id}/invoices/#{invoice.id}/xml"]))
    end
  end

  describe "duplicate warning" do
    setup :stub_pdf

    test "shown when duplicate_of_id is set with link to original", %{
      conn: conn,
      company: company
    } do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{duplicate.id}")

      assert has_element?(view, ~s([data-testid="duplicate-warning"]))

      assert has_element?(
               view,
               ~s(a[href="/c/#{company.id}/invoices/#{original.id}"]),
               "View original"
             )

      assert has_element?(view, "button", "Not a duplicate")
      assert has_element?(view, "button", "Confirm duplicate")
    end

    test "dismiss_duplicate removes the warning", %{conn: conn, company: company} do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{duplicate.id}")

      view |> element("button", "Not a duplicate") |> render_click()

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
    end

    test "confirm_duplicate shows confirmed state", %{conn: conn, company: company} do
      original = insert(:invoice, company: company)

      duplicate =
        insert(:pdf_upload_invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{duplicate.id}")

      view |> element("button", "Confirm duplicate") |> render_click()

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
      assert has_element?(view, ~s([data-testid="duplicate-confirmed"]))
    end

    test "not shown when duplicate_of_id is nil", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      refute has_element?(view, ~s([data-testid="duplicate-warning"]))
    end
  end

  describe "purchase_order display and editing" do
    setup :stub_pdf

    test "displays purchase_order in details table when present", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:invoice, company: company, purchase_order: "PO-LV-001")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ "PO-LV-001"
      assert html =~ "PO</td>"
    end

    test "hides purchase_order row when nil", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, purchase_order: nil)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute html =~ "PO</td>"
    end

    test "edit form includes purchase_order field", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      assert has_element?(view, "input#edit-purchase-order")
    end

    test "saving purchase_order via edit form persists the value", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{"purchase_order" => "PO-SAVED-123"}
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.purchase_order == "PO-SAVED-123"
    end
  end

  describe "extraction fields display and editing" do
    setup :stub_pdf

    test "displays addresses when present", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          seller_address: %{
            street: "ul. Testowa 1",
            city: "Warszawa",
            postal_code: nil,
            country: "PL"
          },
          buyer_address: %{street: "ul. Kupna 5", city: "Kraków", postal_code: nil, country: "PL"}
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=seller-address]", "ul. Testowa 1")
      assert has_element?(view, "[data-testid=buyer-address]", "ul. Kupna 5")
    end

    test "hides addresses when nil", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, seller_address: nil, buyer_address: nil)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      refute has_element?(view, "[data-testid=seller-address]")
      refute has_element?(view, "[data-testid=buyer-address]")
    end

    test "displays sales_date and due_date when present", %{conn: conn, company: company} do
      invoice =
        insert(:invoice,
          company: company,
          sales_date: ~D[2025-01-14],
          due_date: ~D[2025-02-14]
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=sales-date]", "2025-01-14")
      assert has_element?(view, "[data-testid=due-date]", "2025-02-14")
    end

    test "displays iban when present", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company, iban: "PL61109010140000071219812874")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert has_element?(view, "[data-testid=iban]", "PL61109010140000071219812874")
    end

    test "edit form includes iban and date fields", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      assert has_element?(view, "input#edit-sales-date")
      assert has_element?(view, "input#edit-due-date")
      assert has_element?(view, "input#edit-iban")
    end

    test "saving extraction fields via edit form persists values", %{
      conn: conn,
      company: company
    } do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "sales_date" => "2025-06-01",
          "due_date" => "2025-07-01",
          "iban" => "PL61109010140000071219812874"
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.sales_date == ~D[2025-06-01]
      assert updated.due_date == ~D[2025-07-01]
      assert updated.iban == "PL61109010140000071219812874"
    end
  end

  describe "address editing" do
    setup :stub_pdf

    test "edit form shows address inputs pre-filled from existing data", %{
      conn: conn,
      company: company
    } do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          seller_address: %{
            "street" => "ul. Testowa 1",
            "city" => "Warszawa",
            "postal_code" => "00-001",
            "country" => "PL"
          }
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      assert has_element?(view, "input#edit-seller-address-street[value='ul. Testowa 1']")
      assert has_element?(view, "input#edit-seller-address-city[value='Warszawa']")
      assert has_element?(view, "input#edit-seller-address-postal-code[value='00-001']")
      assert has_element?(view, "input#edit-seller-address-country[value='PL']")
    end

    test "saving address fields persists them", %{conn: conn, company: company} do
      invoice = insert(:pdf_upload_invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "seller_address" => %{
            "street" => "ul. Nowa 5",
            "city" => "Kraków",
            "postal_code" => "30-001",
            "country" => "PL"
          }
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.seller_address["street"] == "ul. Nowa 5"
      assert updated.seller_address["city"] == "Kraków"
      assert updated.seller_address["postal_code"] == "30-001"
      assert updated.seller_address["country"] == "PL"
    end

    test "clearing all address sub-fields stores nil", %{conn: conn, company: company} do
      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          seller_address: %{
            "street" => "ul. Testowa 1",
            "city" => "Warszawa",
            "postal_code" => "00-001",
            "country" => "PL"
          }
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      view |> element("button", "Edit") |> render_click()

      view
      |> form("form[phx-submit=save_edit]", %{
        "invoice" => %{
          "seller_address" => %{
            "street" => "",
            "city" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert is_nil(updated.seller_address)
    end
  end

  describe "reviewer role" do
    setup %{conn: _conn} do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-rev-show-1",
          email: "reviewer-show@example.com",
          name: "Reviewer"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
      %{conn: conn, company: company}
    end

    test "reviewer can view expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
      assert html =~ invoice.invoice_number
    end

    test "reviewer is redirected when viewing income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}")
    end
  end
end
