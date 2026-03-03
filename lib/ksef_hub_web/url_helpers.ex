defmodule KsefHubWeb.UrlHelpers do
  @moduledoc """
  Shared URL utility functions for the web layer.
  """

  use KsefHubWeb, :verified_routes

  @doc """
  Returns the default landing path for a company context.

  When a company is available, returns the company-scoped invoices path.
  Falls back to `/companies` when no company is present.
  """
  @spec default_path(%{id: any()} | nil) :: String.t()
  def default_path(nil), do: ~p"/companies"
  def default_path(%{id: id}), do: ~p"/c/#{id}/invoices"

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
