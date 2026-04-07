defmodule KsefHub.InvoiceExtractor.Placeholders do
  @moduledoc """
  Placeholder values the LLM extractor may return when a field is not found.

  All fields in the extraction schema are required (for structured output performance),
  so the model outputs these sentinel values instead of null.
  """

  @placeholders ~w(- -- N/A n/a null `)

  @doc "Returns the list of known extraction placeholder strings."
  @spec values() :: [String.t()]
  def values, do: @placeholders

  @doc "Returns true if the trimmed value is a known extraction placeholder."
  @spec placeholder?(String.t() | nil) :: boolean()
  def placeholder?(nil), do: false

  def placeholder?(value) when is_binary(value) do
    String.trim(value) in @placeholders
  end
end
