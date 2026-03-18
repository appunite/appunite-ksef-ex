defmodule KsefHubWeb.Api.CategoryControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  describe "index" do
    test "returns categories for the token's company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:category, company: company, identifier: "ops:mine")

      other_company = insert(:company)
      insert(:category, company: other_company, identifier: "ops:other")

      conn = conn |> api_conn(token) |> get("/api/categories")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["identifier"] == "ops:mine"
    end

    test "returns empty list when no categories exist", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      conn = conn |> api_conn(token) |> get("/api/categories")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"] == []
    end

    test "returns categories ordered by sort_order then identifier", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:category, company: company, identifier: "b:beta", sort_order: 1)
      insert(:category, company: company, identifier: "a:alpha", sort_order: 0)

      conn = conn |> api_conn(token) |> get("/api/categories")

      body = Jason.decode!(conn.resp_body)
      identifiers = Enum.map(body["data"], & &1["identifier"])
      assert identifiers == ["a:alpha", "b:beta"]
    end
  end

  describe "show" do
    test "returns a category", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company, identifier: "ops:test")

      conn = conn |> api_conn(token) |> get("/api/categories/#{category.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == category.id
    end

    test "returns 404 for category from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      category = insert(:category, company: other_company)

      conn = conn |> api_conn(token) |> get("/api/categories/#{category.id}")

      assert conn.status == 404
    end
  end

  describe "create" do
    test "creates a category with valid attrs", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{identifier: "finance:invoices", emoji: "💰", sort_order: 5})
      conn = conn |> api_conn(token) |> post("/api/categories", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["identifier"] == "finance:invoices"
      assert data["emoji"] == "💰"
      assert data["sort_order"] == 5
    end

    test "returns 422 for invalid identifier format", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{identifier: "no-colon"})
      conn = conn |> api_conn(token) |> post("/api/categories", body)

      assert conn.status == 422
    end

    test "returns 422 for missing identifier", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{emoji: "📦"})
      conn = conn |> api_conn(token) |> post("/api/categories", body)

      assert conn.status == 422
    end

    test "returns 422 for duplicate identifier in same company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:category, company: company, identifier: "ops:dup")

      body = Jason.encode!(%{identifier: "ops:dup"})
      conn = conn |> api_conn(token) |> post("/api/categories", body)

      assert conn.status == 422
    end
  end

  describe "update" do
    test "updates a category", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company, identifier: "ops:old")

      body = Jason.encode!(%{identifier: "ops:new", emoji: "🔥"})
      conn = conn |> api_conn(token) |> put("/api/categories/#{category.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["identifier"] == "ops:new"
      assert data["emoji"] == "🔥"
    end

    test "returns 404 for category from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      category = insert(:category, company: other_company)

      body = Jason.encode!(%{identifier: "ops:hacked"})
      conn = conn |> api_conn(token) |> put("/api/categories/#{category.id}", body)

      assert conn.status == 404
    end

    test "returns 422 for invalid update", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)

      body = Jason.encode!(%{identifier: "bad-format"})
      conn = conn |> api_conn(token) |> put("/api/categories/#{category.id}", body)

      assert conn.status == 422
    end
  end

  describe "delete" do
    test "deletes a category", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)

      conn = conn |> api_conn(token) |> delete("/api/categories/#{category.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["message"] == "Category deleted"
    end

    test "returns 404 for category from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      category = insert(:category, company: other_company)

      conn = conn |> api_conn(token) |> delete("/api/categories/#{category.id}")

      assert conn.status == 404
    end
  end

  describe "permission enforcement" do
    test "accountant can read categories (index)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      insert(:category, company: company, identifier: "ops:test")

      conn = conn |> api_conn(token) |> get("/api/categories")
      assert conn.status == 200
    end

    test "accountant can read category (show)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      category = insert(:category, company: company, identifier: "ops:test")

      conn = conn |> api_conn(token) |> get("/api/categories/#{category.id}")
      assert conn.status == 200
    end

    test "reviewer can read category (show)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      category = insert(:category, company: company, identifier: "ops:test")

      conn = conn |> api_conn(token) |> get("/api/categories/#{category.id}")
      assert conn.status == 200
    end

    test "reviewer can read categories (index)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      insert(:category, company: company, identifier: "ops:test")

      conn = conn |> api_conn(token) |> get("/api/categories")
      assert conn.status == 200
    end

    test "accountant cannot create categories", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:accountant)

      body = Jason.encode!(%{identifier: "ops:test"})
      conn = conn |> api_conn(token) |> post("/api/categories", body)
      assert conn.status == 403
    end

    test "reviewer cannot create categories", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:reviewer)

      body = Jason.encode!(%{identifier: "ops:test"})
      conn = conn |> api_conn(token) |> post("/api/categories", body)
      assert conn.status == 403
    end

    test "admin can create categories", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:admin)

      body = Jason.encode!(%{identifier: "ops:test"})
      conn = conn |> api_conn(token) |> post("/api/categories", body)
      assert conn.status == 201
    end

    test "accountant cannot update categories", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      category = insert(:category, company: company)

      body = Jason.encode!(%{identifier: "ops:updated"})
      conn = conn |> api_conn(token) |> patch("/api/categories/#{category.id}", body)
      assert conn.status == 403
    end

    test "admin can update categories", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:admin)
      category = insert(:category, company: company)

      body = Jason.encode!(%{identifier: "ops:updated"})
      conn = conn |> api_conn(token) |> patch("/api/categories/#{category.id}", body)
      assert conn.status == 200
    end

    test "admin can delete categories", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:admin)
      category = insert(:category, company: company)

      conn = conn |> api_conn(token) |> delete("/api/categories/#{category.id}")
      assert conn.status == 200
    end

    test "accountant cannot delete categories", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      category = insert(:category, company: company)

      conn = conn |> api_conn(token) |> delete("/api/categories/#{category.id}")
      assert conn.status == 403
    end

    test "reviewer cannot update categories", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      category = insert(:category, company: company)

      body = Jason.encode!(%{identifier: "ops:updated"})
      conn = conn |> api_conn(token) |> patch("/api/categories/#{category.id}", body)
      assert conn.status == 403
    end

    test "reviewer cannot delete categories", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      category = insert(:category, company: company)

      conn = conn |> api_conn(token) |> delete("/api/categories/#{category.id}")
      assert conn.status == 403
    end
  end
end
