defmodule KsefHubWeb.FilenameHelpers do
  @moduledoc "Shared filename utilities for downloads."

  @doc "Sanitizes a filename for safe use in Content-Disposition headers."
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\.\-]/u, "_")
    |> String.slice(0, 200)
  end
end
