defmodule KsefHub.Exports.ZipBuilderTest do
  use ExUnit.Case, async: true

  alias KsefHub.Exports.ZipBuilder

  describe "build/3" do
    test "creates valid ZIP with CSV and PDF files" do
      pdf_files = [{"invoice_001.pdf", "fake-pdf-1"}, {"invoice_002.pdf", "fake-pdf-2"}]
      csv_binary = "header\r\nrow1\r\n"

      assert {:ok, zip_binary} = ZipBuilder.build(pdf_files, csv_binary)
      assert is_binary(zip_binary)
      assert byte_size(zip_binary) > 0

      # Verify ZIP contents
      {:ok, entries} = :zip.unzip(zip_binary, [:memory])
      filenames = Enum.map(entries, fn {name, _content} -> to_string(name) end)

      assert "summary.csv" in filenames
      assert "invoice_001.pdf" in filenames
      assert "invoice_002.pdf" in filenames
    end

    test "includes _errors.txt when errors provided" do
      pdf_files = [{"invoice.pdf", "fake-pdf"}]
      csv_binary = "header\r\n"
      errors = ["FV/001: :no_source_content", "FV/002: :timeout"]

      assert {:ok, zip_binary} = ZipBuilder.build(pdf_files, csv_binary, errors: errors)

      {:ok, entries} = :zip.unzip(zip_binary, [:memory])
      filenames = Enum.map(entries, fn {name, _content} -> to_string(name) end)

      assert "_errors.txt" in filenames

      {_, error_content} =
        Enum.find(entries, fn {name, _} -> to_string(name) == "_errors.txt" end)

      assert error_content =~ "FV/001: :no_source_content"
      assert error_content =~ "FV/002: :timeout"
    end

    test "omits _errors.txt when no errors" do
      assert {:ok, zip_binary} = ZipBuilder.build([], "csv")

      {:ok, entries} = :zip.unzip(zip_binary, [:memory])
      filenames = Enum.map(entries, fn {name, _content} -> to_string(name) end)

      refute "_errors.txt" in filenames
    end

    test "creates valid ZIP with only CSV (no PDFs)" do
      assert {:ok, zip_binary} = ZipBuilder.build([], "header\r\n")

      {:ok, entries} = :zip.unzip(zip_binary, [:memory])
      assert length(entries) == 1

      [{name, content}] = entries
      assert to_string(name) == "summary.csv"
      assert content == "header\r\n"
    end

    test "preserves PDF binary content exactly" do
      original_pdf = :crypto.strong_rand_bytes(1024)
      assert {:ok, zip_binary} = ZipBuilder.build([{"test.pdf", original_pdf}], "csv")

      {:ok, entries} = :zip.unzip(zip_binary, [:memory])

      {_, extracted_content} =
        Enum.find(entries, fn {name, _} -> to_string(name) == "test.pdf" end)

      assert extracted_content == original_pdf
    end
  end
end
