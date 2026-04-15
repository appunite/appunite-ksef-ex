defmodule KsefHub.Iban do
  @moduledoc """
  IBAN normalization utilities.

  Strips whitespace, dashes, and upcases the country prefix.
  Used across invoice extraction, payment request changesets,
  and company bank account changesets.
  """

  @iban_min_length 15

  @doc """
  Strips whitespace and dashes from an IBAN, upcases standard country prefixes.

  Returns `nil` when the value is shorter than 15 characters (minimum IBAN length)
  or when the input is nil/empty.

  ## Examples

      iex> KsefHub.Iban.normalize("PL 61 1090 1014 0000 0712 1981 2874")
      "PL61109010140000071219812874"

      iex> KsefHub.Iban.normalize("pl61-1090-1014-0000-0712-1981-2874")
      "PL61109010140000071219812874"

      iex> KsefHub.Iban.normalize(nil)
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: nil

  def normalize(value) do
    stripped = value |> String.trim() |> String.replace(~r/[\s\-]/, "")

    cond do
      String.length(stripped) < @iban_min_length -> nil
      Regex.match?(~r/^[A-Za-z]{2}\d{2}/, stripped) -> String.upcase(stripped)
      true -> stripped
    end
  end
end
