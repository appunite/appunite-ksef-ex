defmodule KsefHub.Invoices.Extraction do
  @moduledoc """
  Extraction and parsing helpers for invoice data.

  Handles mapping raw extraction results (from the invoice-extractor sidecar)
  to invoice attrs, determining extraction completeness, computing billing dates,
  and populating company-side fields based on invoice type.

  This module is used internally by `KsefHub.Invoices` — the public API facade
  delegates to the functions here.
  """

  alias KsefHub.Companies.Company
  alias KsefHub.Invoices.{Invoice, KsefNumber, PurchaseOrder}

  # Fields that must be present for an invoice to be considered fully extracted.
  # `present_value?/1` defines what "present" means (non-nil, non-blank, non-placeholder).
  # For Decimal amounts, zero is treated as present here — `get_extracted_decimal/2`
  # already converts LLM sentinel zeros to nil before status is calculated, so extraction
  # always produces nil (absent) for unfound amounts; zero can only arrive via manual edit.
  #
  # ⚠️  MIGRATION OBLIGATION: adding a field to this list does NOT retroactively fix
  # existing invoices. You MUST also write a backfill migration that sets
  # extraction_status = :partial for invoices that are currently :complete but have
  # the newly-required field missing. See priv/repo/migrations/20260418100000_backfill_extraction_status.exs
  # as a reference.
  @critical_extraction_fields ~w(seller_nip seller_name invoice_number issue_date net_amount gross_amount)a

  @extraction_placeholders KsefHub.InvoiceExtractor.Placeholders.values()

  @address_fields ~w(street city postal_code country)

  @iban_prefix_pattern ~r/^[A-Za-z]{2}\d/

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Returns the list of critical extraction field atoms."
  @spec critical_extraction_fields() :: [atom()]
  def critical_extraction_fields, do: @critical_extraction_fields

  @doc """
  Determines extraction status from a plain attrs map (no struct required).

  Used during KSeF sync to set extraction_status before upsert.
  Returns `:complete` if all critical fields are present, `:partial` otherwise.
  """
  @spec determine_extraction_status_from_attrs(map()) :: :complete | :partial
  def determine_extraction_status_from_attrs(attrs) do
    if all_critical_fields_present?(attrs), do: :complete, else: :partial
  end

  @doc """
  Recalculates extraction status based on the presence of critical fields.

  Merges the given `attrs` over the invoice's current values, then checks
  whether all critical fields are present. Returns updated attrs with the
  new `:extraction_status` value.
  """
  @spec recalculate_extraction_status(Invoice.t(), map()) :: map()
  def recalculate_extraction_status(%Invoice{} = invoice, attrs) do
    merged = invoice |> Map.from_struct() |> Map.merge(atomize_known_keys(attrs))
    Map.put(attrs, :extraction_status, determine_extraction_status_from_attrs(merged))
  end

  @doc """
  Returns the list of critical extraction fields that are missing on the invoice.
  """
  @spec missing_critical_fields(Invoice.t()) :: [atom()]
  def missing_critical_fields(%Invoice{} = invoice) do
    map = Map.from_struct(invoice)

    Enum.filter(@critical_extraction_fields, fn field ->
      not present_value?(Map.get(map, field))
    end)
  end

  @doc """
  Computes a default billing_date from the given attrs map.

  Returns the first day of the month of `sales_date` (falling back to
  `issue_date`), or `nil` if neither is present.
  """
  @spec compute_billing_date(map()) :: Date.t() | nil
  def compute_billing_date(attrs) do
    date = get_attr(attrs, :sales_date) || get_attr(attrs, :issue_date)
    first_of_month(date)
  end

  @doc """
  Populates company-side fields on invoice attrs based on type.

  For expense invoices, sets buyer_nip and buyer_name from the company
  only when extraction didn't provide them. For income invoices, does
  the same for seller_nip and seller_name.
  """
  @spec populate_company_fields(map(), Company.t()) :: map()
  def populate_company_fields(attrs, %Company{} = company) do
    type = attrs[:type] || attrs["type"]

    case type do
      t when t in [:expense, "expense"] ->
        attrs
        |> put_if_blank(:buyer_nip, company.nip)
        |> put_if_blank(:buyer_name, company.name)

      t when t in [:income, "income"] ->
        attrs
        |> put_if_blank(:seller_nip, company.nip)
        |> put_if_blank(:seller_name, company.name)

      _ ->
        attrs
    end
  end

  # -------------------------------------------------------------------
  # Functions called from KsefHub.Invoices (need to be public)
  # -------------------------------------------------------------------

  @doc """
  Maps extraction results (string-keyed map) to invoice attrs (atom-keyed map).

  Used by both initial PDF upload creation and re-extraction.
  """
  @spec extracted_to_invoice_attrs(map()) :: map()
  def extracted_to_invoice_attrs(extracted) do
    iban = extract_iban(extracted)
    explicit_account = get_extracted_string(extracted, "bank_account_number")

    # When bank_iban contained a non-IBAN value (e.g. Indonesian local account),
    # extract_iban/1 returns nil. Fall back the raw value to account_number
    # so the data isn't lost. Explicit bank_account_number takes priority.
    account_number =
      explicit_account || non_iban_fallback(extracted, iban)

    %{
      seller_nip: get_extracted_nip(extracted, "seller_nip"),
      seller_name: get_extracted_string(extracted, "seller_name"),
      buyer_nip: get_extracted_nip(extracted, "buyer_nip"),
      buyer_name: get_extracted_string(extracted, "buyer_name"),
      invoice_number: get_extracted_string(extracted, "invoice_number"),
      issue_date: get_extracted_date(extracted, "issue_date"),
      net_amount: get_extracted_decimal(extracted, "net_amount"),
      gross_amount: get_extracted_decimal(extracted, "gross_amount"),
      currency: get_extracted_string(extracted, "currency"),
      ksef_number: get_extracted_ksef_number(extracted),
      purchase_order: get_extracted_purchase_order(extracted, "purchase_order"),
      sales_date: get_extracted_date(extracted, "sales_date"),
      due_date: get_extracted_date(extracted, "due_date"),
      iban: iban,
      swift_bic: get_extracted_string(extracted, "bank_swift_bic"),
      bank_name: get_extracted_string(extracted, "bank_name"),
      bank_address: get_extracted_string(extracted, "bank_address"),
      routing_number: get_extracted_string(extracted, "bank_routing_number"),
      account_number: account_number,
      payment_instructions: get_extracted_string(extracted, "bank_notes"),
      seller_address: get_extracted_address(extracted, "seller_address_"),
      buyer_address: get_extracted_address(extracted, "buyer_address_")
    }
  end

  @doc """
  Extracts a trimmed string from extraction data, filtering placeholders and blanks.
  """
  @spec get_extracted_string(map(), String.t()) :: String.t() | nil
  def get_extracted_string(data, key) do
    case data[key] do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "" or trimmed in @extraction_placeholders, do: nil, else: trimmed

      _ ->
        nil
    end
  end

  @doc """
  Checks if a value looks like it could be an IBAN (starts with a 2-letter country code).
  """
  @spec iban_candidate?(String.t() | nil) :: boolean()
  def iban_candidate?(nil), do: false

  def iban_candidate?(value) do
    stripped = value |> String.trim() |> String.replace(~r/[\s\-]/, "")
    Regex.match?(@iban_prefix_pattern, stripped)
  end

  @doc """
  Builds invoice attrs for a PDF upload with extracted fields.
  """
  @spec build_pdf_upload_attrs(
          map(),
          Ecto.UUID.t(),
          binary(),
          String.t(),
          String.t() | nil,
          atom()
        ) ::
          map()
  def build_pdf_upload_attrs(
        extracted,
        company_id,
        pdf_binary,
        type,
        filename,
        extraction_status
      ) do
    attrs = extracted_to_invoice_attrs(extracted)

    attrs
    |> Map.put(:currency, attrs[:currency] || "PLN")
    |> Map.merge(%{
      source: :pdf_upload,
      type: type,
      company_id: company_id,
      pdf_content: pdf_binary,
      original_filename: filename,
      extraction_status: extraction_status
    })
  end

  @doc """
  Determines extraction status from a raw extractor response map.

  Preprocesses the map through `extracted_to_invoice_attrs/1` before checking,
  so that sentinel values produced by the LLM (e.g. integer `0` for unfound
  amounts) are normalised to `nil` before the presence check runs. Use this
  function whenever the input comes directly from the extractor sidecar.

  Use `determine_extraction_status_from_attrs/1` for already-processed attrs
  (e.g. KSeF sync, manual-edit recalculation).
  """
  @spec determine_extraction_status(map()) :: :complete | :partial
  def determine_extraction_status(extracted) do
    extracted
    |> extracted_to_invoice_attrs()
    |> determine_extraction_status_from_attrs()
  end

  @doc """
  Converts string keys to existing atoms where possible.
  """
  @spec atomize_known_keys(map()) :: map()
  def atomize_known_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) -> {safe_to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  @doc """
  Fills in default billing dates from sales_date/issue_date when not already set.
  """
  @spec maybe_default_billing_date(map()) :: map()
  def maybe_default_billing_date(attrs) do
    if has_attr?(attrs, :billing_date_from) or has_attr?(attrs, :billing_date_to) do
      attrs
    else
      case compute_billing_date(attrs) do
        nil -> attrs
        date -> attrs |> Map.put(:billing_date_from, date) |> Map.put(:billing_date_to, date)
      end
    end
  end

  @doc """
  Like `maybe_default_billing_date/1`, but for updates -- only fills in billing dates
  when the existing invoice doesn't already have them set (preserves manual edits).
  """
  @spec maybe_default_billing_date_for_update(map(), Invoice.t()) :: map()
  def maybe_default_billing_date_for_update(attrs, %Invoice{} = invoice) do
    if is_nil(invoice.billing_date_from) and is_nil(invoice.billing_date_to) do
      maybe_default_billing_date(attrs)
    else
      attrs
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  @spec first_of_month(term()) :: Date.t() | nil
  defp first_of_month(%Date{year: y, month: m}), do: Date.new!(y, m, 1)

  defp first_of_month(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} ->
        first_of_month(date)

      _ ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _} -> first_of_month(DateTime.to_date(dt))
          _ -> nil
        end
    end
  end

  defp first_of_month(_), do: nil

  @spec has_attr?(map(), atom()) :: boolean()
  defp has_attr?(attrs, key) do
    Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key))
  end

  @spec get_attr(map(), atom()) :: term()
  defp get_attr(attrs, key) do
    attrs[key] || attrs[Atom.to_string(key)]
  end

  @spec put_if_blank(map(), atom(), String.t() | nil) :: map()
  defp put_if_blank(attrs, key, value) do
    existing = Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

    if is_nil(existing) or existing == "" do
      Map.put(attrs, key, value)
    else
      attrs
    end
  end

  @spec all_critical_fields_present?(map()) :: boolean()
  defp all_critical_fields_present?(map) do
    Enum.all?(@critical_extraction_fields, fn field ->
      value = Map.get(map, field) || Map.get(map, Atom.to_string(field))
      present_value?(value)
    end)
  end

  @spec present_value?(term()) :: boolean()
  defp present_value?(nil), do: false

  defp present_value?(s) when is_binary(s) do
    trimmed = String.trim(s)
    trimmed != "" and trimmed not in @extraction_placeholders
  end

  defp present_value?(_), do: true

  @spec get_extracted_address(map(), String.t()) :: map() | nil
  defp get_extracted_address(data, prefix) do
    addr =
      Map.new(@address_fields, fn field ->
        {field, get_extracted_string(data, prefix <> field)}
      end)

    cleaned =
      addr
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(cleaned) == 0, do: nil, else: cleaned
  end

  @spec get_extracted_nip(map(), String.t()) :: String.t() | nil
  defp get_extracted_nip(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> normalize_nip(value)
    end
  end

  @spec get_extracted_ksef_number(map()) :: String.t() | nil
  defp get_extracted_ksef_number(data) do
    raw = get_extracted_string(data, "ksef_number")
    seller_nip = get_extracted_nip(data, "seller_nip")
    KsefNumber.validate(raw, seller_nip)
  end

  @spec get_extracted_purchase_order(map(), String.t()) :: String.t() | nil
  defp get_extracted_purchase_order(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> PurchaseOrder.extract(value)
    end
  end

  # Returns the raw bank_iban value when it was rejected as non-IBAN
  # (i.e. extract_iban returned nil), so it can populate account_number.
  # Values that look like truncated IBANs (start with a country prefix)
  # are NOT demoted — they're partial IBANs, not local account numbers.
  @spec non_iban_fallback(map(), String.t() | nil) :: String.t() | nil
  defp non_iban_fallback(_extracted, iban) when not is_nil(iban), do: nil

  defp non_iban_fallback(extracted, nil) do
    raw = get_extracted_string(extracted, "bank_iban")
    if iban_candidate?(raw), do: nil, else: raw
  end

  # Extracts and normalizes IBAN from the extracted data.
  # Returns nil when the value is shorter than 15 chars (minimum IBAN length),
  # routing it to :account_number instead via extracted_to_invoice_attrs/1.
  @spec extract_iban(map()) :: String.t() | nil
  defp extract_iban(extracted) do
    case get_extracted_string(extracted, "bank_iban") do
      nil -> nil
      raw -> normalize_iban(raw)
    end
  end

  @spec normalize_iban(String.t()) :: String.t() | nil
  defp normalize_iban(value), do: KsefHub.Iban.normalize(value)

  @spec normalize_nip(String.t()) :: String.t()
  defp normalize_nip(value), do: KsefHub.Nip.normalize(value)

  @spec get_extracted_date(map(), String.t()) :: Date.t() | nil
  defp get_extracted_date(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> parse_date(value)
    end
  end

  @spec parse_date(String.t()) :: Date.t() | nil
  defp parse_date(value) do
    with {:error, _} <- Date.from_iso8601(value),
         :error <- parse_datetime_as_date(value),
         :error <- parse_naive_datetime_as_date(value) do
      nil
    else
      {:ok, date} -> date
    end
  end

  @spec parse_datetime_as_date(String.t()) :: {:ok, Date.t()} | :error
  defp parse_datetime_as_date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, DateTime.to_date(dt)}
      _ -> :error
    end
  end

  @spec parse_naive_datetime_as_date(String.t()) :: {:ok, Date.t()} | :error
  defp parse_naive_datetime_as_date(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> {:ok, NaiveDateTime.to_date(ndt)}
      _ -> :error
    end
  end

  # Returns nil for zero values since the extraction schema uses all-required fields,
  # so the LLM returns 0 for amounts not found on the invoice. Treating 0 as nil
  # ensures determine_extraction_status correctly marks these as :partial.
  @spec get_extracted_decimal(map(), String.t()) :: Decimal.t() | nil
  defp get_extracted_decimal(data, key) do
    result =
      case data[key] do
        nil -> nil
        value when is_integer(value) -> Decimal.new(value)
        value when is_float(value) -> Decimal.from_float(value)
        value when is_binary(value) -> parse_decimal(value)
        _ -> nil
      end

    if result && not Decimal.equal?(result, 0), do: result, else: nil
  end

  @spec parse_decimal(String.t()) :: Decimal.t() | nil
  defp parse_decimal(value) do
    case value |> String.trim() |> Decimal.parse() do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  @spec safe_to_existing_atom(String.t()) :: atom() | String.t()
  defp safe_to_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> str
  end
end
