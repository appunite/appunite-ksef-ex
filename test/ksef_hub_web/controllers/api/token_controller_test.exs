defmodule KsefHubWeb.Api.TokenControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts

  defp create_owner_with_token do
    user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
    company = insert(:company)
    insert(:membership, user: user, company: company, role: "owner")

    {:ok, %{token: token}} =
      Accounts.create_api_token(user.id, company.id, %{name: "API Token"})

    %{user: user, company: company, token: token}
  end

  defp api_conn(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  describe "index" do
    test "lists tokens for the token's company only", %{conn: conn} do
      %{user: user, company: company, token: token} = create_owner_with_token()

      # Create another token for same user+company
      {:ok, _} =
        Accounts.create_api_token(user.id, company.id, %{name: "Second Token"})

      # Create token for different company
      company2 = insert(:company)
      insert(:membership, user: user, company: company2, role: "owner")
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
      insert(:membership, user: user, company: company2, role: "owner")

      {:ok, %{api_token: other_token}} =
        Accounts.create_api_token(user.id, company2.id, %{name: "Other"})

      conn = conn |> api_conn(token) |> delete("/api/tokens/#{other_token.id}")

      assert conn.status == 404
    end
  end

  describe "owner-only enforcement" do
    test "non-owner cannot revoke tokens via API", %{conn: conn} do
      # Create a company with an owner who creates a token
      owner = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
      company = insert(:company)
      insert(:membership, user: owner, company: company, role: "owner")

      {:ok, %{api_token: target}} =
        Accounts.create_api_token(owner.id, company.id, %{name: "Target Token"})

      # Create an accountant with a token for the same company
      # (inserted directly via factory to bypass owner check)
      accountant = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
      insert(:membership, user: accountant, company: company, role: "accountant")

      {:ok, %{token: acct_plain_token}} =
        Accounts.create_api_token(accountant.id, %{name: "Acct Token"})

      # Set company_id on the accountant's token so ApiAuth derives the company
      acct_api_token = KsefHub.Repo.get_by!(Accounts.ApiToken, created_by_id: accountant.id)

      acct_api_token
      |> Ecto.Changeset.change(company_id: company.id)
      |> KsefHub.Repo.update!()

      conn = conn |> api_conn(acct_plain_token) |> delete("/api/tokens/#{target.id}")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["error"] =~ "Only company owners"
    end
  end
end
