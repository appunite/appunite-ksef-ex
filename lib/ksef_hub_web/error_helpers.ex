defmodule KsefHubWeb.ErrorHelpers do
  @moduledoc """
  Shared helper for sanitizing error reasons before logging.
  Strips large payloads (XML, stderr output) and returns a short diagnostic string.
  """

  @max_length 200

  @doc """
  Returns a short, safe string representation of an error reason.
  Redacts large binaries (XML content, stderr output) to prevent log pollution.
  """
  @spec sanitize_error(term()) :: String.t()
  def sanitize_error(reason) when is_binary(reason) do
    truncate(reason)
  end

  def sanitize_error({tag, code, output}) when is_atom(tag) and is_binary(output) do
    "#{tag} (code: #{code}, output: #{byte_size(output)} bytes)"
  end

  def sanitize_error({tag, reason}) when is_atom(tag) do
    "#{tag}: #{sanitize_error(reason)}"
  end

  def sanitize_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  def sanitize_error(reason) do
    reason |> inspect() |> truncate()
  end

  defp truncate(str) when byte_size(str) > @max_length do
    String.slice(str, 0, @max_length) <> "..."
  end

  defp truncate(str), do: str
end
