defmodule KsefHubWeb.ChangesetHelpers do
  @moduledoc """
  Shared helpers for formatting Ecto changeset errors in JSON API responses.
  """

  @doc """
  Traverses changeset errors into a map of human-readable messages.
  """
  @spec changeset_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
