defmodule KsefHubWeb.UrlHelpers do
  @moduledoc """
  Shared URL utility functions for the web layer.
  """

  @doc """
  Sanitizes a return_to path to prevent open-redirect attacks.

  Returns `nil` for any path that contains a host or doesn't start with "/".
  """
  @spec sanitize_return_to(String.t() | nil) :: String.t() | nil
  def sanitize_return_to(nil), do: nil
  def sanitize_return_to(""), do: nil

  def sanitize_return_to(path) when is_binary(path) do
    uri = URI.parse(path)

    if is_nil(uri.host) && String.starts_with?(path, "/") do
      path
    else
      nil
    end
  end
end
