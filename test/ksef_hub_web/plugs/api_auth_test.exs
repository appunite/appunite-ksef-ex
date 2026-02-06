defmodule KsefHubWeb.Plugs.ApiAuthTest do
  use KsefHubWeb.ConnCase, async: true

  alias KsefHub.Accounts

  describe "ApiAuth plug" do
    test "allows request with valid bearer token", %{conn: conn} do
      {:ok, %{token: token}} = Accounts.create_api_token(%{name: "Test Token"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      # Should not return 401 (may return 200 or other non-auth error)
      refute conn.status == 401
    end

    test "rejects request without authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "Invalid or missing API token"
    end

    test "rejects request with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
    end

    test "rejects request with revoked token", %{conn: conn} do
      {:ok, %{token: token, api_token: api_token}} =
        Accounts.create_api_token(%{name: "Revoked"})

      {:ok, _} = Accounts.revoke_api_token(api_token.id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
    end

    test "tracks token usage on successful auth", %{conn: conn} do
      {:ok, %{token: token, api_token: api_token}} =
        Accounts.create_api_token(%{name: "Track Me"})

      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/api/invoices")

      updated = KsefHub.Repo.get!(Accounts.ApiToken, api_token.id)
      assert updated.request_count == 1
      assert updated.last_used_at != nil
    end
  end
end
