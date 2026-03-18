defmodule KsefHubWeb.Api.TagControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  describe "index" do
    test "returns tags for the token's company with usage_count", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      tag = insert(:tag, company: company, name: "urgent")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      other_company = insert(:company)
      insert(:tag, company: other_company, name: "other")

      conn = conn |> api_conn(token) |> get("/api/tags")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["name"] == "urgent"
      assert hd(body["data"])["usage_count"] == 1
      assert hd(body["data"])["type"] == "expense"
    end

    test "returns empty list when no tags exist", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      conn = conn |> api_conn(token) |> get("/api/tags")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"] == []
    end

    test "filters tags by type query param", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:tag, company: company, name: "expense-tag", type: :expense)
      insert(:tag, company: company, name: "income-tag", type: :income)

      conn_expense = conn |> api_conn(token) |> get("/api/tags?type=expense")
      body = Jason.decode!(conn_expense.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["name"] == "expense-tag"

      conn_income = conn |> api_conn(token) |> get("/api/tags?type=income")
      body = Jason.decode!(conn_income.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["name"] == "income-tag"
    end
  end

  describe "show" do
    test "returns a tag", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      tag = insert(:tag, company: company, name: "urgent")

      conn = conn |> api_conn(token) |> get("/api/tags/#{tag.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == tag.id
    end

    test "returns 404 for tag from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      tag = insert(:tag, company: other_company)

      conn = conn |> api_conn(token) |> get("/api/tags/#{tag.id}")

      assert conn.status == 404
    end
  end

  describe "create" do
    test "creates a tag with valid attrs", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{name: "urgent", description: "Needs attention"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["name"] == "urgent"
      assert data["description"] == "Needs attention"
      assert data["type"] == "expense"
    end

    test "creates an income tag when type is specified", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{name: "revenue", type: "income"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["name"] == "revenue"
      assert data["type"] == "income"
    end

    test "returns 422 for missing name", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{description: "no name"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)

      assert conn.status == 422
    end

    test "returns 422 for duplicate name in same company and type", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:tag, company: company, name: "dup", type: :expense)

      body = Jason.encode!(%{name: "dup"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)

      assert conn.status == 422
    end

    test "allows duplicate name across different types", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:tag, company: company, name: "shared", type: :expense)

      body = Jason.encode!(%{name: "shared", type: "income"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)

      assert conn.status == 201
    end
  end

  describe "update" do
    test "updates a tag", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      tag = insert(:tag, company: company, name: "old")

      body = Jason.encode!(%{name: "new"})
      conn = conn |> api_conn(token) |> put("/api/tags/#{tag.id}", body)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["name"] == "new"
    end

    test "returns 404 for tag from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      tag = insert(:tag, company: other_company)

      body = Jason.encode!(%{name: "hacked"})
      conn = conn |> api_conn(token) |> put("/api/tags/#{tag.id}", body)

      assert conn.status == 404
    end

    test "returns 422 for invalid update", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      tag = insert(:tag, company: company)

      body = Jason.encode!(%{name: ""})
      conn = conn |> api_conn(token) |> put("/api/tags/#{tag.id}", body)

      assert conn.status == 422
    end
  end

  describe "delete" do
    test "deletes a tag", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      tag = insert(:tag, company: company)

      conn = conn |> api_conn(token) |> delete("/api/tags/#{tag.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["message"] == "Tag deleted"
    end

    test "returns 404 for tag from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      tag = insert(:tag, company: other_company)

      conn = conn |> api_conn(token) |> delete("/api/tags/#{tag.id}")

      assert conn.status == 404
    end
  end

  describe "permission enforcement" do
    test "accountant can read tags (index)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      insert(:tag, company: company, name: "test")

      conn = conn |> api_conn(token) |> get("/api/tags")
      assert conn.status == 200
    end

    test "reviewer can read tags (index)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      insert(:tag, company: company, name: "test")

      conn = conn |> api_conn(token) |> get("/api/tags")
      assert conn.status == 200
    end

    test "accountant cannot create tags", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:accountant)

      body = Jason.encode!(%{name: "test"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)
      assert conn.status == 403
    end

    test "reviewer cannot create tags", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:reviewer)

      body = Jason.encode!(%{name: "test"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)
      assert conn.status == 403
    end

    test "admin can create tags", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:admin)

      body = Jason.encode!(%{name: "test"})
      conn = conn |> api_conn(token) |> post("/api/tags", body)
      assert conn.status == 201
    end

    test "accountant cannot update tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      tag = insert(:tag, company: company, name: "original")

      body = Jason.encode!(%{name: "updated"})
      conn = conn |> api_conn(token) |> patch("/api/tags/#{tag.id}", body)
      assert conn.status == 403
    end

    test "reviewer cannot update tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      tag = insert(:tag, company: company, name: "original")

      body = Jason.encode!(%{name: "updated"})
      conn = conn |> api_conn(token) |> patch("/api/tags/#{tag.id}", body)
      assert conn.status == 403
    end

    test "admin can update tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:admin)
      tag = insert(:tag, company: company, name: "original")

      body = Jason.encode!(%{name: "updated"})
      conn = conn |> api_conn(token) |> patch("/api/tags/#{tag.id}", body)
      assert conn.status == 200
    end

    test "accountant cannot delete tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      tag = insert(:tag, company: company, name: "to-delete")

      conn = conn |> api_conn(token) |> delete("/api/tags/#{tag.id}")
      assert conn.status == 403
    end

    test "reviewer cannot delete tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      tag = insert(:tag, company: company, name: "to-delete")

      conn = conn |> api_conn(token) |> delete("/api/tags/#{tag.id}")
      assert conn.status == 403
    end

    test "admin can delete tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:admin)
      tag = insert(:tag, company: company, name: "to-delete")

      conn = conn |> api_conn(token) |> delete("/api/tags/#{tag.id}")
      assert conn.status == 200
    end
  end
end
