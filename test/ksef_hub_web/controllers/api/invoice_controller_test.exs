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
      assert Jason.decode!(conn.resp_body)["data"] == []
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
end
