defmodule KsefHub.InboundEmail.CcParser do
  @moduledoc """
  Parses RFC 5322 CC headers and builds deduplicated CC lists for reply emails.

  Handles both display-name formats (`"Alice" <a@b.com>`) and bare addresses (`a@b.com`).
  """

  @doc """
  Parses a raw CC header string into a list of `{name, email}` tuples suitable for Swoosh.

  Returns `[]` for `nil` or empty strings.

  ## Examples

      iex> parse_cc_header("Alice <alice@example.com>, bob@example.com")
      [{"Alice", "alice@example.com"}, {"bob@example.com", "bob@example.com"}]

      iex> parse_cc_header(nil)
      []
  """
  @spec parse_cc_header(String.t() | nil) :: [{String.t(), String.t()}]
  def parse_cc_header(nil), do: []
  def parse_cc_header(""), do: []

  def parse_cc_header(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_address/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Builds a merged, deduplicated CC list from original CC header and company CC address.

  Excludes any email addresses in `exclude` (compared case-insensitively).
  Returns a list of `{name, email}` tuples suitable for Swoosh.

  ## Examples

      iex> build_cc_list("team@co.com", "boss@co.com", ["sender@co.com"])
      [{"team@co.com", "team@co.com"}, {"boss@co.com", "boss@co.com"}]
  """
  @spec build_cc_list(String.t() | nil, String.t() | nil, [String.t()]) :: [
          {String.t(), String.t()}
        ]
  def build_cc_list(original_cc, company_cc, exclude \\ []) do
    original = parse_cc_header(original_cc)
    company = parse_company_cc(company_cc)
    exclude_set = MapSet.new(exclude, &String.downcase/1)

    (original ++ company)
    |> deduplicate()
    |> Enum.reject(fn {_name, email} -> MapSet.member?(exclude_set, String.downcase(email)) end)
  end

  @spec parse_address(String.t()) :: {String.t(), String.t()} | nil
  defp parse_address(raw) do
    trimmed = String.trim(raw)
    if trimmed == "", do: nil, else: do_parse_address(trimmed)
  end

  @spec do_parse_address(String.t()) :: {String.t(), String.t()} | nil
  defp do_parse_address(str) do
    case Regex.run(~r/<([^>]+)>/, str) do
      [_, email] ->
        name =
          str
          |> String.replace(~r/<[^>]+>/, "")
          |> String.trim()
          |> String.trim("\"")
          |> String.trim()

        if name == "" do
          {email, email}
        else
          {name, email}
        end

      nil ->
        if String.contains?(str, "@") do
          {str, str}
        else
          nil
        end
    end
  end

  @spec parse_company_cc(String.t() | nil) :: [{String.t(), String.t()}]
  defp parse_company_cc(nil), do: []
  defp parse_company_cc(""), do: []
  defp parse_company_cc(cc), do: [{cc, cc}]

  @spec deduplicate([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  defp deduplicate(addresses) do
    addresses
    |> Enum.reduce({[], MapSet.new()}, fn {name, email}, {acc, seen} ->
      key = String.downcase(email)

      if MapSet.member?(seen, key) do
        {acc, seen}
      else
        {[{name, email} | acc], MapSet.put(seen, key)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
