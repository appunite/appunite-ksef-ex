defmodule KsefHubWeb.Api.TagController do
  @moduledoc """
  REST API controller for tag operations.

  All actions are scoped to the company associated with the authenticated API token.
  """

  use KsefHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import KsefHubWeb.ChangesetHelpers
  import KsefHubWeb.JsonHelpers, only: [tag_json: 1, atomize_keys: 2]

  alias KsefHub.Invoices
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  plug KsefHubWeb.Plugs.RequirePermission, :manage_tags when action in [:create, :update, :delete]

  @tag_allowed_keys ~w(name description)

  tags(["Tags"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List tags",
    description:
      "Returns all tags for the company with usage counts, ordered by popularity then name.",
    responses: %{
      200 =>
        {"Tag list with usage counts, ordered by popularity then name", "application/json",
         Schemas.TagListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Lists all tags for the token's company."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    company_id = conn.assigns.current_company.id
    tags = Invoices.list_tags(company_id)
    json(conn, %{data: Enum.map(tags, &tag_json/1)})
  end

  operation(:show,
    summary: "Get tag",
    description: "Returns a single tag by ID.",
    parameters: [
      id: [
        in: :path,
        description: "Tag UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Tag", "application/json", Schemas.TagResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Tag not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Returns a single tag by UUID."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    case Invoices.get_tag(company_id, id) do
      {:ok, tag} ->
        json(conn, %{data: tag_json(tag)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tag not found"})
    end
  end

  operation(:create,
    summary: "Create tag",
    description: "Creates a new tag for the company.",
    request_body: {"Tag to create", "application/json", Schemas.CreateTagRequest},
    responses: %{
      201 => {"Created tag", "application/json", Schemas.TagResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — name is required and must be unique within the company",
         "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Creates a tag for the token's company."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    company_id = conn.assigns.current_company.id

    case Invoices.create_tag(company_id, atomize_keys(params, @tag_allowed_keys)) do
      {:ok, tag} ->
        conn
        |> put_status(:created)
        |> json(%{data: tag_json(tag)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:update,
    summary: "Update tag",
    description: "Updates an existing tag.",
    parameters: [
      id: [
        in: :path,
        description: "Tag UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Tag updates", "application/json", Schemas.UpdateTagRequest},
    responses: %{
      200 => {"Updated tag", "application/json", Schemas.TagResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Tag not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — name must be unique within the company", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Updates a tag."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id

    with {:ok, tag} <- Invoices.get_tag(company_id, id),
         {:ok, updated} <- Invoices.update_tag(tag, atomize_keys(params, @tag_allowed_keys)) do
      json(conn, %{data: tag_json(updated)})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tag not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:delete,
    summary: "Delete tag",
    description: "Deletes a tag. All invoice-tag associations are removed.",
    parameters: [
      id: [
        in: :path,
        description: "Tag UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Tag deleted — all invoice-tag associations are removed", "application/json",
         Schemas.MessageResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Tag not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Deletes a tag."
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    with {:ok, tag} <- Invoices.get_tag(company_id, id),
         {:ok, _} <- Invoices.delete_tag(tag) do
      json(conn, %{message: "Tag deleted"})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tag not found"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete tag"})
    end
  end
end
