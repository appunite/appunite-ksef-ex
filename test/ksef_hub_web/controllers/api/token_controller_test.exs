defmodule KsefHubWeb.Api.TokenControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  alias KsefHub.Accounts

  describe "index" do
    test "lists tokens for the token's company only", %{conn: conn} do
      %{user: user, company: company, token: token} = create_owner_with_token()

      # Create another token for same user+company
      {:ok, _} =
        Accounts.create_api_token(user.id, company.id, %{name: "Second Token"})

      # Create token for different company
      company2 = insert(:company)
      insert(:membership, user: user, company: company2, role: :owner)
      {:ok, _} = Accounts.create_api_token(user.id, company2.id, %{name: "Other Company"})

      conn = conn |> api_conn(token) |> get("/api/tokens")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      names = Enum.map(body["data"], & &1["name"])
      assert "API Token" in names
      assert "Second Token" in names
      refute "Other Company" in names
    end
  end

  describe "create" do
    test "creates a new token scoped to the token's company", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "New Token", description: "Test"})

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["name"] == "New Token"
      assert body["data"]["token"]
      assert body["message"] =~ "Store this token"
    end

    test "returns 422 for missing name", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      conn = conn |> api_conn(token) |> post("/api/tokens", %{description: "No name"})

      assert conn.status == 422
    end

    test "admin can create token", %{conn: conn} do
      {:ok, %{token: token}} = create_admin_with_token()

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "Admin Token"})

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["name"] == "Admin Token"
    end

    test "accountant can create token", %{conn: conn} do
      {:ok, %{token: token}} = create_accountant_with_token()

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "Accountant Token"})

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["name"] == "Accountant Token"
    end

    test "returns 403 when reviewer tries to create token", %{conn: conn} do
      {:ok, %{token: token}} = create_reviewer_with_token()

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "Should Fail"})

      assert conn.status == 403
    end
  end

  describe "delete" do
    test "revokes a token from the same company", %{conn: conn} do
      %{user: user, company: company, token: token} = create_owner_with_token()

      {:ok, %{api_token: target}} =
        Accounts.create_api_token(user.id, company.id, %{name: "To Revoke"})

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{target.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["message"] =~ "revoked"
    end

    test "returns 404 for token from different company", %{conn: conn} do
      %{user: user, token: token} = create_owner_with_token()

      company2 = insert(:company)
      insert(:membership, user: user, company: company2, role: :owner)

      {:ok, %{api_token: other_token}} =
        Accounts.create_api_token(user.id, company2.id, %{name: "Other"})

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{other_token.id}")

      assert conn.status == 404
    end
  end

  describe "role-based enforcement" do
    test "reviewer cannot access token endpoints", %{conn: conn} do
      {:ok, %{token: token}} = create_reviewer_with_token()

      conn = conn |> api_conn(token) |> get("/api/tokens")

      assert conn.status == 403
    end

    test "reviewer cannot revoke tokens via API", %{conn: conn} do
      {:ok, %{token: token}} = create_reviewer_with_token()

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{Ecto.UUID.generate()}")

      assert conn.status == 403
    end
  end
end
