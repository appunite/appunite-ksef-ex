defmodule KsefHub.Invoices.Reextraction do
  @moduledoc """
  Re-extraction and re-parsing of invoice data from stored files.

  Provides functions to re-parse FA(3) XML or re-extract data from stored PDFs
  via the invoice-extractor sidecar. Used when the parser or extractor is
  improved and existing invoices need to pick up the changes without a full
  KSeF re-sync.

  Functions here are internal API — callers should go through the
  `KsefHub.Invoices` facade.
  """

  require Logger

  alias KsefHub.Companies.Company
  alias KsefHub.Files

  alias KsefHub.InvoiceExtractor.ContextBuilder

  alias KsefHub.Invoices
  alias KsefHub.Invoices.{DuplicateDetector, Duplicates, Extraction, Invoice, NipVerifier, Parser}

  @doc """
  Re-parses an invoice's stored FA(3) XML and updates its fields.

  Useful when the parser is improved (e.g. new field extraction) and existing
  invoices need to pick up the changes without a full KSeF re-sync.

  Returns `{:ok, updated_invoice}` on success, `{:error, reason}` on failure.
  """
  @spec reparse_from_stored_xml(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def reparse_from_stored_xml(%Invoice{} = invoice, opts \\ []) do
    with {:ok, xml_content} <- load_xml_content(invoice),
         {:ok, parsed} <- Parser.parse(xml_content) do
      attrs =
        parsed
        |> Map.drop([:line_items])
        |> Map.put(:type, invoice.type)
        |> Map.put(:currency, parsed[:currency] || invoice.currency || "PLN")
        |> Extraction.maybe_default_billing_date_for_update(invoice)

      attrs = Invoices.recalculate_extraction_status(invoice, attrs)

      Invoices.update_invoice(invoice, attrs, opts)
    end
  end

  @doc """
  Re-extracts data from an invoice's stored PDF file.

  Calls the extraction sidecar to re-parse the PDF, then updates the invoice
  with the newly extracted fields. Only works for invoices that have a stored
  PDF file (source: :pdf_upload or :email).

  Returns `{:ok, updated_invoice}` on success, `{:error, reason}` on failure.
  """
  @spec re_extract_invoice(Invoice.t(), Company.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def re_extract_invoice(%Invoice{} = invoice, %Company{} = company, opts \\ []) do
    with {:ok, pdf_binary} <- load_pdf_content(invoice),
         {:ok, extracted} <- do_re_extract(company, invoice, pdf_binary),
         :ok <- NipVerifier.verify_for_type(extracted, company.nip, invoice.type) do
      apply_extraction_results(invoice, extracted, company, opts)
    end
  end

  @spec load_xml_content(Invoice.t()) :: {:ok, binary()} | {:error, :no_xml}
  defp load_xml_content(%Invoice{xml_file: %{content: content}}) when is_binary(content),
    do: {:ok, content}

  defp load_xml_content(%Invoice{xml_file_id: xml_file_id}) when not is_nil(xml_file_id) do
    case Files.get_file(xml_file_id) do
      %{content: content} when is_binary(content) -> {:ok, content}
      _ -> {:error, :no_xml}
    end
  end

  defp load_xml_content(_invoice), do: {:error, :no_xml}

  @spec load_pdf_content(Invoice.t()) :: {:ok, binary()} | {:error, :no_pdf}
  defp load_pdf_content(%Invoice{pdf_file: %{content: content}}) when is_binary(content),
    do: {:ok, content}

  defp load_pdf_content(%Invoice{pdf_file_id: pdf_file_id}) when not is_nil(pdf_file_id) do
    case Files.get_file(pdf_file_id) do
      %{content: content} when is_binary(content) -> {:ok, content}
      _ -> {:error, :no_pdf}
    end
  end

  defp load_pdf_content(_invoice), do: {:error, :no_pdf}

  @spec do_re_extract(Company.t(), Invoice.t(), binary()) ::
          {:ok, map()} | {:error, term()}
  defp do_re_extract(company, invoice, pdf_binary) do
    context = ContextBuilder.build(company, invoice.type)
    filename = invoice.original_filename || "invoice.pdf"
    invoice_extractor().extract(pdf_binary, filename: filename, context: context)
  end

  @spec apply_extraction_results(Invoice.t(), map(), Company.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp apply_extraction_results(invoice, extracted, company, opts) do
    extracted_attrs = Extraction.extracted_to_invoice_attrs(extracted)

    # When bank_iban was present but rejected as non-IBAN (e.g. short local
    # account number), we must explicitly clear the iban field so a stale
    # value from a previous extraction doesn't persist.
    # However, values that look like truncated IBANs (start with a country
    # prefix like "PL") should NOT trigger clearing — they're partial IBANs,
    # not a signal that the account is non-IBAN.
    raw_bank_iban = Extraction.get_extracted_string(extracted, "bank_iban")

    clear_iban? =
      not is_nil(raw_bank_iban) and
        is_nil(Map.get(extracted_attrs, :iban)) and
        not Extraction.iban_candidate?(raw_bank_iban)

    # For re-extraction, only overwrite fields that have non-nil extracted values.
    # This preserves manually-edited data when re-extraction returns partial results.
    attrs =
      extracted_attrs
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> then(fn attrs -> if clear_iban?, do: Map.put(attrs, :iban, nil), else: attrs end)
      |> Map.put(:type, invoice.type)
      |> Extraction.populate_company_fields(company)
      |> Extraction.maybe_default_billing_date_for_update(invoice)

    # Preserve existing currency if extraction didn't provide one
    attrs =
      if Map.has_key?(attrs, :currency),
        do: attrs,
        else: Map.put(attrs, :currency, invoice.currency || "PLN")

    # Determine extraction status from merged invoice + new attrs so that
    # fields already present on the invoice (from prior extraction or manual
    # edit) count towards completeness.
    attrs = Invoices.recalculate_extraction_status(invoice, attrs)

    with {:ok, updated} <- Invoices.update_invoice(invoice, attrs, opts) do
      updated = maybe_detect_duplicate_after_extraction(updated, opts)
      Invoices.maybe_enqueue_prediction(attrs.extraction_status, updated)
      {:ok, updated}
    end
  end

  # After re-extraction populates fields, check if this invoice is now a duplicate.
  # Only runs when the invoice is not already marked as a duplicate.
  @spec maybe_detect_duplicate_after_extraction(Invoice.t(), keyword()) :: Invoice.t()
  defp maybe_detect_duplicate_after_extraction(%Invoice{duplicate_of_id: id} = invoice, _opts)
       when not is_nil(id),
       do: invoice

  defp maybe_detect_duplicate_after_extraction(%Invoice{} = invoice, opts) do
    attrs = Map.from_struct(invoice)

    case DuplicateDetector.find_original_id(invoice.company_id, attrs, exclude_id: invoice.id) do
      nil -> invoice
      original_id -> Duplicates.mark_as_duplicate(invoice, original_id, opts)
    end
  end

  @spec invoice_extractor() :: module()
  defp invoice_extractor do
    Application.get_env(:ksef_hub, :invoice_extractor, KsefHub.InvoiceExtractor.Client)
  end
end
