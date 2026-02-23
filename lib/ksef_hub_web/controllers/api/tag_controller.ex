defmodule KsefHubWeb.Api.TagController do
  @moduledoc """
  REST API controller for tag operations.

  All actions are scoped to the company associated with the authenticated API token.
  """

  use KsefHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import KsefHubWeb.ChangesetHelpers

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Tag
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  tags(["Tags"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List tags",
    description:
      "Returns all tags for the company with usage counts, ordered by popularity then name.",
    responses: %{
      200 => {"Tag list", "application/json", Schemas.TagListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
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
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
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
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Creates a tag for the token's company."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    company_id = conn.assigns.current_company.id
    attrs = Map.take(params, ~w(name description))

    case Invoices.create_tag(company_id, atomize_tag_keys(attrs)) do
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
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Updates a tag."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id

    with {:ok, tag} <- Invoices.get_tag(company_id, id),
         attrs = Map.take(params, ~w(name description)),
         {:ok, updated} <- Invoices.update_tag(tag, atomize_tag_keys(attrs)) do
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
      200 => {"Deleted", "application/json", Schemas.MessageResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Deletes a tag."
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    case Invoices.get_tag(company_id, id) do
      {:ok, tag} ->
        {:ok, _} = Invoices.delete_tag(tag)
        json(conn, %{message: "Tag deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Tag not found"})
    end
  end

  # --- Private ---

  @tag_allowed_keys ~w(name description)

  @spec atomize_tag_keys(map()) :: map()
  defp atomize_tag_keys(params) do
    for {key, value} <- params,
        key in @tag_allowed_keys,
        into: %{} do
      {String.to_existing_atom(key), value}
    end
  end

  @spec tag_json(Tag.t()) :: map()
  defp tag_json(tag) do
    %{
      id: tag.id,
      name: tag.name,
      description: tag.description,
      usage_count: tag.usage_count,
      inserted_at: tag.inserted_at,
      updated_at: tag.updated_at
    }
  end
end
