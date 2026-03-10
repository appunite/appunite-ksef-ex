defmodule KsefHubWeb.Api.TokenControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  alias KsefHub.Accounts

  describe "index" do
    test "lists tokens for the token's company only", %{conn: conn} do
      %{user: user, company: company, token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

      conn = conn |> api_conn(token) |> post("/api/tokens", %{description: "No name"})

      assert conn.status == 422
    end

    test "admin can create token", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:admin)

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "Admin Token"})

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["name"] == "Admin Token"
    end

    test "accountant can create token", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:accountant)

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "Accountant Token"})

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["name"] == "Accountant Token"
    end

    test "reviewer can create token", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:reviewer)

      conn =
        conn
        |> api_conn(token)
        |> post("/api/tokens", %{name: "Reviewer Token"})

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["data"]["name"] == "Reviewer Token"
    end
  end

  describe "delete" do
    test "revokes a token from the same company", %{conn: conn} do
      %{user: user, company: company, token: token} = create_user_with_token(:owner)

      {:ok, %{api_token: target}} =
        Accounts.create_api_token(user.id, company.id, %{name: "To Revoke"})

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{target.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["message"] =~ "revoked"
    end

    test "returns 404 for token from different company", %{conn: conn} do
      %{user: user, token: token} = create_user_with_token(:owner)

      company2 = insert(:company)
      insert(:membership, user: user, company: company2, role: :owner)

      {:ok, %{api_token: other_token}} =
        Accounts.create_api_token(user.id, company2.id, %{name: "Other"})

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{other_token.id}")

      assert conn.status == 404
    end
  end

  describe "role-based enforcement" do
    test "reviewer can list tokens", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:reviewer)

      conn = conn |> api_conn(token) |> get("/api/tokens")

      assert conn.status == 200
    end

    test "reviewer can revoke own tokens via API", %{conn: conn} do
      {:ok, %{user: user, company: company, token: token}} = create_user_with_token(:reviewer)

      {:ok, %{api_token: target}} =
        Accounts.create_api_token(user.id, company.id, %{name: "To Revoke"})

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{target.id}")

      assert conn.status == 200
      refute KsefHub.Repo.get!(Accounts.ApiToken, target.id).is_active
    end

    test "reviewer cannot revoke another member's token", %{conn: conn} do
      {:ok, %{company: company, token: reviewer_token}} = create_user_with_token(:reviewer)

      other_user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
      insert(:membership, user: other_user, company: company, role: :owner)

      {:ok, %{api_token: other_token}} =
        Accounts.create_api_token(other_user.id, company.id, %{name: "Other Token"})

      conn = conn |> api_conn(reviewer_token) |> delete("/api/tokens/#{other_token.id}")

      assert conn.status == 404
      assert KsefHub.Repo.get!(Accounts.ApiToken, other_token.id).is_active
    end
  end
end
