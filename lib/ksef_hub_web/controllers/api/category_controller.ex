defmodule KsefHubWeb.Api.CategoryController do
  @moduledoc """
  REST API controller for category operations.

  All actions are scoped to the company associated with the authenticated API token.
  """

  use KsefHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import KsefHubWeb.ChangesetHelpers
  import KsefHubWeb.JsonHelpers, only: [category_json: 1, atomize_keys: 2]

  alias KsefHub.Invoices
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  plug KsefHubWeb.Plugs.RequirePermission, :manage_categories when action in [:create, :update, :delete]

  @category_allowed_keys ~w(name emoji description sort_order)

  tags(["Categories"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List categories",
    description: "Returns all categories for the company, ordered by sort_order then name.",
    responses: %{
      200 =>
        {"Category list ordered by sort_order then name", "application/json",
         Schemas.CategoryListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Lists all categories for the token's company."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    company_id = conn.assigns.current_company.id
    categories = Invoices.list_categories(company_id)
    json(conn, %{data: Enum.map(categories, &category_json/1)})
  end

  operation(:show,
    summary: "Get category",
    description: "Returns a single category by ID.",
    parameters: [
      id: [
        in: :path,
        description: "Category UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Category", "application/json", Schemas.CategoryResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Category not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Returns a single category by UUID."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    case Invoices.get_category(company_id, id) do
      {:ok, category} ->
        json(conn, %{data: category_json(category)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Category not found"})
    end
  end

  operation(:create,
    summary: "Create category",
    description: "Creates a new category for the company.",
    request_body: {"Category to create", "application/json", Schemas.CreateCategoryRequest},
    responses: %{
      201 => {"Created category", "application/json", Schemas.CategoryResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — name is required and must be unique within the company",
         "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Creates a category for the token's company."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    company_id = conn.assigns.current_company.id

    case Invoices.create_category(company_id, atomize_keys(params, @category_allowed_keys)) do
      {:ok, category} ->
        conn
        |> put_status(:created)
        |> json(%{data: category_json(category)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:update,
    summary: "Update category",
    description: "Updates an existing category.",
    parameters: [
      id: [
        in: :path,
        description: "Category UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Category updates", "application/json", Schemas.UpdateCategoryRequest},
    responses: %{
      200 => {"Updated category", "application/json", Schemas.CategoryResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Category not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — name must be unique within the company", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Updates a category."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id

    with {:ok, category} <- Invoices.get_category(company_id, id),
         {:ok, updated} <-
           Invoices.update_category(category, atomize_keys(params, @category_allowed_keys)) do
      json(conn, %{data: category_json(updated)})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Category not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:delete,
    summary: "Delete category",
    description:
      "Deletes a category. Invoices assigned to this category will have their category cleared.",
    parameters: [
      id: [
        in: :path,
        description: "Category UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Category deleted — invoices with this category will have it cleared",
         "application/json", Schemas.MessageResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Category not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Deletes a category."
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    with {:ok, category} <- Invoices.get_category(company_id, id),
         {:ok, _} <- Invoices.delete_category(category) do
      json(conn, %{message: "Category deleted"})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Category not found"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete category"})
    end
  end
end
