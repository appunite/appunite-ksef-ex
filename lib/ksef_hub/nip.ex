defmodule KsefHub.Nip do
  @moduledoc """
  Polish NIP (tax identification number) normalization utilities.

  Handles common formatting variants from PDF extractors and KSeF XML:
  PL prefix, dashes, spaces.
  """

  @pl_prefix ~r/^PL/i
  @non_digits ~r/[\s\-]/
  @ten_digits ~r/^\d{10}$/

  @doc """
  Strips PL prefix, dashes, and spaces from a Polish NIP.

  Returns the 10-digit canonical form for valid Polish NIPs.
  Returns the original trimmed value for foreign tax IDs (e.g. "DE123456789").

  ## Examples

      iex> KsefHub.Nip.normalize("PL 7831812112")
      "7831812112"

      iex> KsefHub.Nip.normalize("783-181-21-12")
      "7831812112"

      iex> KsefHub.Nip.normalize("DE123456789")
      "DE123456789"

      iex> KsefHub.Nip.normalize(nil)
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: ""

  def normalize(value) do
    trimmed = String.trim(value)

    stripped =
      trimmed
      |> String.replace(@pl_prefix, "")
      |> String.replace(@non_digits, "")

    if Regex.match?(@ten_digits, stripped), do: stripped, else: trimmed
  end
end
