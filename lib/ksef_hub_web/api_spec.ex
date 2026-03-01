defmodule KsefHubWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the KSeF Hub REST API.

  Generates the OpenAPI 3.0 spec served at `/api/openapi`.
  """

  alias OpenApiSpex.{Info, OpenApi, Paths, SecurityScheme, Server}

  @behaviour OpenApi

  @doc """
  Returns the OpenAPI 3.0 specification for the KSeF Hub REST API.

  Called by `OpenApiSpex.Plug.PutApiSpec` on each request through the `:api` pipeline.
  The result is cached by the plug after the first call.
  """
  @impl OpenApi
  @spec spec() :: OpenApi.t()
  def spec do
    build_spec()
    |> OpenApiSpex.resolve_schema_modules()
  end

  @spec build_spec() :: OpenApi.t()
  defp build_spec do
    %OpenApi{
      info: info(),
      servers: servers(),
      paths: Paths.from_router(KsefHubWeb.Router),
      components: components(),
      security: security()
    }
  end

  @spec info() :: Info.t()
  defp info do
    %Info{
      title: "Invoi API",
      version: "1.0.0",
      description: """
      REST API for Poland's National e-Invoice System (KSeF).
      Provides invoice querying, approval workflows, PDF generation,
      and API token management.
      """
    }
  end

  @spec servers() :: [Server.t()]
  defp servers do
    [%Server{url: "/", description: "Current server"}]
  end

  @spec components() :: OpenApiSpex.Components.t()
  defp components do
    %OpenApiSpex.Components{
      securitySchemes: %{
        "bearer" => %SecurityScheme{
          type: "http",
          scheme: "bearer",
          description: "API token obtained from the Tokens endpoint or admin UI."
        }
      }
    }
  end

  @spec security() :: [map()]
  defp security do
    [%{"bearer" => []}]
  end
end
