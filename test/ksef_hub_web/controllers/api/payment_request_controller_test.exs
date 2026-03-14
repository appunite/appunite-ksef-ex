defmodule KsefHubWeb.Api.PaymentRequestControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  alias KsefHub.PaymentRequests

  describe "index" do
    test "lists payment requests for the company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:payment_request, company: company, recipient_name: "Acme Corp")
      insert(:payment_request, company: company, recipient_name: "Beta Ltd")

      conn = conn |> api_conn(token) |> get("/api/payment-requests")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 2
      assert body["meta"]["total_count"] == 2
    end

    test "scopes to company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:payment_request, company: company, recipient_name: "Mine")
      other = insert(:company)
      insert(:payment_request, company: other, recipient_name: "Not Mine")

      conn = conn |> api_conn(token) |> get("/api/payment-requests")
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["recipient_name"] == "Mine"
    end

    test "filters by status", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:payment_request, company: company, status: :pending)
      insert(:payment_request, company: company, status: :paid)

      conn = conn |> api_conn(token) |> get("/api/payment-requests?status=pending")
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["status"] == "pending"
    end

    test "paginates results", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      for _ <- 1..5, do: insert(:payment_request, company: company)

      conn = conn |> api_conn(token) |> get("/api/payment-requests?page=1&per_page=2")
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 2
      assert body["meta"]["total_count"] == 5
      assert body["meta"]["total_pages"] == 3
    end

    test "accountant can list payment requests", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:accountant)
      conn = conn |> api_conn(token) |> get("/api/payment-requests")
      assert conn.status == 200
    end

    test "returns 401 without auth", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/json") |> get("/api/payment-requests")
      assert conn.status == 401
    end
  end

  describe "create" do
    test "creates a payment request", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)

      params = %{
        recipient_name: "Dostawca Sp. z o.o.",
        amount: "1230.00",
        currency: "PLN",
        title: "Invoice FV/2026/001",
        iban: "PL61109010140000071219812874"
      }

      conn = conn |> api_conn(token) |> post("/api/payment-requests", params)
      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["recipient_name"] == "Dostawca Sp. z o.o."
      assert body["data"]["status"] == "pending"

      # Verify persisted
      prs = PaymentRequests.list_payment_requests(company.id)
      assert length(prs) == 1
    end

    test "returns 422 for invalid params", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      conn = conn |> api_conn(token) |> post("/api/payment-requests", %{})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"]
    end

    test "accountant cannot create payment requests", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:accountant)

      params = %{
        recipient_name: "Test",
        amount: "100.00",
        currency: "PLN",
        title: "Test",
        iban: "PL61109010140000071219812874"
      }

      conn = conn |> api_conn(token) |> post("/api/payment-requests", params)
      assert conn.status == 403
    end
  end

  describe "mark_paid" do
    test "marks a payment request as paid", %{conn: conn} do
      %{company: company, token: token, user: user} = create_user_with_token(:owner)
      pr = insert(:payment_request, company: company, created_by: user, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/payment-requests/#{pr.id}/mark-paid")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["status"] == "paid"
    end

    test "returns 404 for non-existent request", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      conn =
        conn
        |> api_conn(token)
        |> post("/api/payment-requests/#{Ecto.UUID.generate()}/mark-paid")

      assert conn.status == 404
    end

    test "accountant cannot mark as paid", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      pr = insert(:payment_request, company: company, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/payment-requests/#{pr.id}/mark-paid")
      assert conn.status == 403
    end

    test "cannot mark another company's payment request as paid", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      pr = insert(:payment_request, company: other_company, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/payment-requests/#{pr.id}/mark-paid")
      assert conn.status == 404
    end
  end

  describe "response fields" do
    test "includes note and paid_at in response", %{conn: conn} do
      %{company: company, token: token, user: user} = create_user_with_token(:owner)

      insert(:payment_request,
        company: company,
        created_by: user,
        note: "Internal memo",
        status: :paid,
        paid_at: ~U[2026-03-10 12:00:00.000000Z]
      )

      conn = conn |> api_conn(token) |> get("/api/payment-requests")
      body = Jason.decode!(conn.resp_body)
      pr = hd(body["data"])
      assert pr["note"] == "Internal memo"
      assert pr["paid_at"] != nil
    end
  end
end
