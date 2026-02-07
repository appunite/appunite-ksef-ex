defmodule KsefHubWeb.Plugs.ApiAuthTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts

  defp create_test_token(attrs \\ %{}) do
    user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
    Accounts.create_api_token(user.id, Map.merge(%{name: "Test Token"}, attrs))
  end

  describe "ApiAuth plug" do
    test "allows request with valid bearer token", %{conn: conn} do
      {:ok, %{token: token}} = create_test_token()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      # Should not return 401 (may return 200 or other non-auth error)
      refute conn.status == 401
    end

    test "rejects request without authorization header with WWW-Authenticate", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "Invalid or missing API token"
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects request with invalid token with WWW-Authenticate", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects expired token", %{conn: conn} do
      user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
      expired_at = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, %{token: token}} =
        Accounts.create_api_token(user.id, %{name: "Expired", expires_at: expired_at})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "expired"
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "rejects request with revoked token", %{conn: conn} do
      user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")

      {:ok, %{token: token, api_token: api_token}} =
        Accounts.create_api_token(user.id, %{name: "Revoked"})

      {:ok, _} = Accounts.revoke_api_token(user.id, api_token.id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("accept", "application/json")
        |> get("/api/invoices")

      assert conn.status == 401
    end

    test "tracks token usage on successful auth", %{conn: conn} do
      {:ok, %{token: token, api_token: api_token}} = create_test_token(%{name: "Track Me"})

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
