defmodule KsefHubWeb.ApiSpecTest do
  @moduledoc """
  Tests that ensure every API endpoint is documented in the OpenAPI spec.

  These tests act as a safety net: if a developer adds a new controller
  action under /api without an `operation(...)` annotation, the test suite
  fails with a clear message telling them which route is missing docs.
  """

  use ExUnit.Case, async: true

  alias KsefHubWeb.ApiSpec

  @api_scope "/api"
  # Routes that are infrastructure, not user-facing API endpoints
  @excluded_routes ["/api/openapi"]

  setup_all do
    spec = ApiSpec.spec()
    %{spec: spec}
  end

  describe "route coverage" do
    test "every API route has a corresponding OpenAPI operation", %{spec: spec} do
      missing =
        Enum.reject(api_routes(), fn {path, verb, _plug, _action} ->
          path in @excluded_routes or has_operation?(spec, path, verb)
        end)

      if missing != [] do
        missing_details =
          Enum.map_join(missing, "\n", fn {path, verb, plug, action} ->
            "  #{String.upcase(to_string(verb))} #{path} (#{inspect(plug)}.#{action})"
          end)

        flunk("""
        The following API routes have no OpenAPI operation spec.
        Add an `operation(:action_name, ...)` block in the controller.

        #{missing_details}
        """)
      end
    end

    test "no OpenAPI paths are documented that don't exist in the router", %{spec: spec} do
      router_paths =
        api_routes()
        |> Enum.map(fn {path, _verb, _plug, _action} -> phoenix_path_to_openapi(path) end)
        |> MapSet.new()

      documented_paths = spec.paths |> Map.keys() |> MapSet.new()

      orphaned = MapSet.difference(documented_paths, router_paths)

      if MapSet.size(orphaned) > 0 do
        flunk("""
        The following OpenAPI paths don't match any router route.
        Remove or update the stale operation specs.

          #{Enum.join(orphaned, "\n  ")}
        """)
      end
    end
  end

  describe "spec structure" do
    test "spec has valid info section", %{spec: spec} do
      assert spec.info.title != nil
      assert spec.info.version != nil
    end

    test "spec declares bearer security scheme", %{spec: spec} do
      assert %{"bearer" => scheme} = spec.components.securitySchemes
      assert scheme.type == "http"
      assert scheme.scheme == "bearer"
    end

    test "every operation has at least one success response (2xx)", %{spec: spec} do
      missing =
        all_operations(spec)
        |> Enum.reject(fn {_id, _path, _verb, operation} ->
          operation.responses
          |> Map.keys()
          |> Enum.any?(&success_code?/1)
        end)

      if missing != [] do
        details = format_operation_list(missing)
        flunk("Operations missing a success (2xx) response:\n#{details}")
      end
    end

    test "every operation has at least one error response (4xx/5xx)", %{spec: spec} do
      missing =
        all_operations(spec)
        |> Enum.reject(fn {_id, _path, _verb, operation} ->
          operation.responses
          |> Map.keys()
          |> Enum.any?(&error_code?/1)
        end)

      if missing != [] do
        details = format_operation_list(missing)
        flunk("Operations missing an error (4xx/5xx) response:\n#{details}")
      end
    end

    test "every operation has a summary", %{spec: spec} do
      missing =
        all_operations(spec)
        |> Enum.reject(fn {_id, _path, _verb, operation} ->
          is_binary(operation.summary) and operation.summary != ""
        end)

      if missing != [] do
        details = format_operation_list(missing)
        flunk("Operations missing a summary:\n#{details}")
      end
    end
  end

  # --- Helpers ---

  @http_verbs [:get, :post, :put, :patch, :delete]

  @spec api_routes() :: [{String.t(), atom(), module(), atom()}]
  defp api_routes do
    KsefHubWeb.Router.__routes__()
    |> Enum.filter(fn route ->
      String.starts_with?(route.path, @api_scope) and route.verb in @http_verbs
    end)
    |> Enum.map(fn route -> {route.path, route.verb, route.plug, route.plug_opts} end)
  end

  @spec phoenix_path_to_openapi(String.t()) :: String.t()
  defp phoenix_path_to_openapi(path) do
    # Phoenix uses :param, OpenAPI uses {param}
    Regex.replace(~r/:([a-zA-Z_][a-zA-Z0-9_]*)/, path, "{\\1}")
  end

  @spec has_operation?(OpenApiSpex.OpenApi.t(), String.t(), atom()) :: boolean()
  defp has_operation?(spec, path, verb) do
    case Map.get(spec.paths, phoenix_path_to_openapi(path)) do
      nil -> false
      path_item -> Map.has_key?(path_item, verb)
    end
  end

  @spec format_operation_list([{String.t(), String.t(), atom(), OpenApiSpex.Operation.t()}]) ::
          String.t()
  defp format_operation_list(operations) do
    Enum.map_join(operations, "\n", fn {id, path, verb, _op} ->
      "  #{String.upcase(to_string(verb))} #{path} (#{id})"
    end)
  end

  @spec success_code?(integer() | atom() | String.t()) :: boolean()
  defp success_code?(code) when is_integer(code), do: code >= 200 and code < 300

  defp success_code?(code) do
    case parse_status_code(code) do
      {:ok, int} -> int >= 200 and int < 300
      :default -> true
      :error -> false
    end
  end

  @spec error_code?(integer() | atom() | String.t()) :: boolean()
  defp error_code?(code) when is_integer(code), do: code >= 400

  defp error_code?(code) do
    case parse_status_code(code) do
      {:ok, int} -> int >= 400
      :default -> true
      :error -> false
    end
  end

  @spec parse_status_code(atom() | String.t()) :: {:ok, integer()} | :default | :error
  defp parse_status_code(:default), do: :default
  defp parse_status_code("default"), do: :default

  defp parse_status_code(code) do
    case Integer.parse("#{code}") do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  @spec all_operations(OpenApiSpex.OpenApi.t()) :: [
          {String.t(), String.t(), atom(), OpenApiSpex.Operation.t()}
        ]
  defp all_operations(spec) do
    for {path, path_item} <- spec.paths,
        verb <- @http_verbs,
        operation = Map.get(path_item, verb),
        operation != nil do
      {operation.operationId || "#{verb} #{path}", path, verb, operation}
    end
  end
end
