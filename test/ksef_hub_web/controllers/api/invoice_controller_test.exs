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
end
