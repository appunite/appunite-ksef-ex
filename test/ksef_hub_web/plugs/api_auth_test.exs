defmodule KsefHubWeb.Plugs.ApiAuthTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHubWeb.ApiTestHelpers

  alias KsefHub.Accounts

  describe "ApiAuth plug" do
    test "assigns api_token and current_company for valid bearer token", %{conn: conn} do
      %{token: token, company: company} = create_owner_with_token()

      conn =
        conn
        |> api_conn(token)
        |> get("/api/invoices")

      refute conn.status == 401
      assert conn.assigns.api_token
      assert conn.assigns.current_company.id == company.id
    end

    test "rejects request without authorization header with WWW-Authenticate", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "Invalid or missing API token"
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects request with invalid token with WWW-Authenticate", %{conn: conn} do
      conn =
        conn
        |> api_conn("invalid-token")
        |> get("/api/invoices")

      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects expired token", %{conn: conn} do
      expired_at = DateTime.add(DateTime.utc_now(), -3600, :second)
      %{token: token} = create_owner_with_token(%{expires_at: expired_at})

      conn =
        conn
        |> api_conn(token)
        |> get("/api/invoices")

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "expired"
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects request with revoked token", %{conn: conn} do
      %{user: user, company: company, token: token, api_token: api_token} =
        create_owner_with_token()

      {:ok, _} = Accounts.revoke_api_token(user.id, company.id, api_token.id)

      conn =
        conn
        |> api_conn(token)
        |> get("/api/invoices")

      assert conn.status == 401
    end

    test "tracks token usage on successful auth", %{conn: conn} do
      %{token: token, api_token: api_token} = create_owner_with_token(%{name: "Track Me"})

      conn
      |> api_conn(token)
      |> get("/api/invoices")

      updated = KsefHub.Repo.get!(Accounts.ApiToken, api_token.id)
      assert updated.request_count == 1
      assert updated.last_used_at != nil
    end
  end
end
