defmodule KsefHub.Invoices.CostLine do
  @moduledoc "Static enum of cost line values for mapping expenses to business cost centers."

  @type t :: :growth | :heads | :service | :service_delivery | :client_success

  @values [:growth, :heads, :service, :service_delivery, :client_success]

  @labels %{
    growth: "Growth",
    heads: "Heads",
    service: "Service",
    service_delivery: "Service delivery",
    client_success: "Client success"
  }

  @doc "Returns the list of valid cost line values."
  @spec values() :: [t()]
  def values, do: @values

  @doc "Returns the human-readable label for a cost line value."
  @spec label(t()) :: String.t()
  def label(value) when is_atom(value), do: Map.fetch!(@labels, value)

  @doc "Returns all values with their labels as a keyword list."
  @spec options() :: [{String.t(), t()}]
  def options, do: Enum.map(@values, fn v -> {label(v), v} end)

  @doc "Casts a string to a cost line atom. Returns `:error` for invalid values."
  @spec cast(String.t() | nil) :: {:ok, t() | nil} | :error
  def cast(nil), do: {:ok, nil}
  def cast(""), do: {:ok, nil}

  def cast(value) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in @values, do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end
end
