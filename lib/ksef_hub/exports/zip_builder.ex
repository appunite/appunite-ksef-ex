defmodule KsefHub.Exports.ZipBuilder do
  @moduledoc "Builds ZIP archive in memory from PDF files and CSV summary. Pure function, no side effects."

  @doc """
  Creates a ZIP archive from a list of named files and a CSV summary.

  ## Parameters
    * `pdf_files` - list of `{filename, binary}` tuples for PDF content
    * `csv_binary` - the CSV summary content
    * `opts` - keyword list with optional `:errors` list of error strings

  ## Returns
    * `{:ok, zip_binary}` on success
    * `{:error, reason}` on failure
  """
  @spec build([{String.t(), binary()}], binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def build(pdf_files, csv_binary, opts \\ []) do
    errors = Keyword.get(opts, :errors, [])

    entries =
      [{~c"summary.csv", csv_binary} | Enum.map(pdf_files, &to_zip_entry/1)]

    entries =
      if errors != [] do
        error_content = Enum.join(errors, "\n") <> "\n"
        entries ++ [{~c"_errors.txt", error_content}]
      else
        entries
      end

    case :zip.create(~c"export.zip", entries, [:memory]) do
      {:ok, {_filename, zip_binary}} -> {:ok, zip_binary}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec to_zip_entry({String.t(), binary()}) :: {charlist(), binary()}
  defp to_zip_entry({filename, content}) do
    {String.to_charlist(filename), content}
  end
end
