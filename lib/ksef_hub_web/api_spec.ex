defmodule KsefHubWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the KSeF Hub REST API.

  Generates the OpenAPI 3.0 spec served at `/api/openapi`.
  """

  alias OpenApiSpex.{Info, OpenApi, Paths, SecurityScheme, Server}

  @behaviour OpenApi

  @impl OpenApi
  @spec spec() :: OpenApi.t()
  def spec do
    %OpenApi{
      info: %Info{
        title: "KSeF Hub API",
        version: "1.0.0",
        description: """
        REST API for Poland's National e-Invoice System (KSeF).
        Provides invoice querying, approval workflows, PDF generation,
        and API token management.
        """
      },
      servers: [
        %Server{url: "/", description: "Current server"}
      ],
      paths: Paths.from_router(KsefHubWeb.Router),
      components: %OpenApiSpex.Components{
        securitySchemes: %{
          "bearer" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description: "API token obtained from the Tokens endpoint or admin UI."
          }
        }
      },
      security: [%{"bearer" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
