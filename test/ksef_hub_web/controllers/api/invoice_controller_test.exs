defmodule KsefHubWeb.Api.InvoiceControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  describe "index" do
    test "returns invoices for the token's company without company_id param", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, seller_name: "My Seller")

      other_company = insert(:company)
      insert(:invoice, company: other_company, seller_name: "Other Seller")

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["seller_name"] == "My Seller"
    end

    test "returns empty list when company has no invoices", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"] == []
      assert body["meta"]["total_count"] == 0
    end

    test "returns paginated response with meta", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()

      for i <- 1..5 do
        insert(:invoice, company: company, invoice_number: "FV/#{i}")
      end

      conn = conn |> api_conn(token) |> get("/api/invoices?page=1&per_page=2")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 2
      assert body["meta"]["page"] == 1
      assert body["meta"]["per_page"] == 2
      assert body["meta"]["total_count"] == 5
      assert body["meta"]["total_pages"] == 3
    end

    test "defaults to page 1 per_page 25", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      assert body["meta"]["page"] == 1
      assert body["meta"]["per_page"] == 25
    end

    test "does not include xml_content in list response", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, xml_content: "<xml>data</xml>")

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      invoice = hd(body["data"])
      refute Map.has_key?(invoice, "xml_content")
    end
  end

  describe "show" do
    test "returns invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == invoice.id
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")
      end
    end
  end

  describe "approve" do
    test "approves expense invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company, type: "expense", status: "pending")

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "approved"
    end

    test "returns 404 when approving invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, type: "expense", status: "pending")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")
      end
    end
  end

  describe "reject" do
    test "rejects expense invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company, type: "expense", status: "pending")

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "rejected"
    end

    test "returns 404 when rejecting invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, type: "expense", status: "pending")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")
      end
    end
  end

  describe "xml" do
    test "returns XML content with correct headers", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      xml = "<Faktura>test</Faktura>"

      invoice =
        insert(:invoice,
          company: company,
          xml_content: xml,
          invoice_number: "FV/2025/001"
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/xml"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_2025_001.xml"
      assert conn.resp_body == xml
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, xml_content: "<xml/>")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")
      end
    end
  end

  describe "create" do
    test "creates a manual invoice and returns 201", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      body =
        Jason.encode!(%{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/001",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["source"] == "manual"
      assert data["type"] == "expense"
      assert data["seller_nip"] == "1234567890"
      assert is_nil(data["duplicate_of_id"])
    end

    test "creates manual invoice and detects duplicate by ksef_number", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      existing = insert(:invoice, ksef_number: "dup-ksef-123", company: company)

      body =
        Jason.encode!(%{
          type: "expense",
          ksef_number: "dup-ksef-123",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/002",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["duplicate_of_id"] == existing.id
      assert data["duplicate_status"] == "suspected"
    end

    test "returns 422 with validation errors for invalid data", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      body = Jason.encode!(%{type: "expense"})

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"]
    end
  end

  describe "confirm_duplicate" do
    test "confirms a suspected duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "confirm-orig", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "confirm-orig",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: "suspected"
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/confirm-duplicate")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["duplicate_status"] == "confirmed"
    end

    test "returns 422 for non-duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/confirm-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice is not a duplicate"
    end
  end

  describe "dismiss_duplicate" do
    test "dismisses a suspected duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "dismiss-orig", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "dismiss-orig",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: "suspected"
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/dismiss-duplicate")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["duplicate_status"] == "dismissed"
    end

    test "returns 422 for non-duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/dismiss-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice is not a duplicate"
    end
  end

  describe "xml with nil xml_content" do
    test "returns 422 for invoice without xml_content", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:manual_invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no XML content"
    end
  end

  describe "source filter" do
    test "filters invoices by source in index", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, source: "ksef")
      insert(:manual_invoice, company: company, source: "manual")

      conn = conn |> api_conn(token) |> get("/api/invoices?source=manual")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["source"] == "manual"
    end
  end

  describe "reviewer role scoping" do
    test "reviewer token returns only expense invoices from index", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      insert(:invoice, company: company, type: "income", seller_name: "Income Seller")
      insert(:invoice, company: company, type: "expense", seller_name: "Expense Seller")

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["type"] == "expense"
      assert body["meta"]["total_count"] == 1
    end

    test "reviewer token returns 404 for income invoice show", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: "income")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{income.id}")
      end
    end

    test "reviewer token can access expense invoice show", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      expense = insert(:invoice, company: company, type: "expense")

      conn = conn |> api_conn(token) |> get("/api/invoices/#{expense.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == expense.id
    end

    test "reviewer token returns 404 for income invoice approve", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: "income")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{income.id}/approve")
      end
    end

    test "reviewer token returns 404 for income invoice reject", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: "income")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{income.id}/reject")
      end
    end

    test "reviewer token returns 404 for income invoice xml", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: "income")

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{income.id}/xml")
      end
    end
  end
end
