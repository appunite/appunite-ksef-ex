defmodule KsefHubWeb.UploadHelpers do
  @moduledoc """
  Shared helpers for LiveView file upload UI (formatting, error messages).
  """

  @doc "Formats a byte count as a human-readable string (e.g. `\"1.5 KB\"`)."
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  @doc "Converts a `Phoenix.LiveView` upload error atom to a user-friendly message."
  @spec upload_error_to_string(atom()) :: String.t()
  def upload_error_to_string(:too_large), do: "File is too large."
  def upload_error_to_string(:not_accepted), do: "Invalid file type."
  def upload_error_to_string(:too_many_files), do: "Only one file allowed."
  def upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
