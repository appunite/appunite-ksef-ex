defmodule KsefHub.Invoices.DuplicateDetector do
  @moduledoc """
  Detects duplicate invoices within a company.

  ## Decision tree (first match wins)

    1. Same KSeF number in company              → duplicate
       (KSeF sync + email re-upload with KSeF number extracted)

    2. Both have KSeF numbers, different         → NOT duplicate
       (two KSeF numbers are definitively distinct invoices)

    3. At most one has a KSeF number, match on:
         company_id + invoice_number + issue_date + net_amount
         + seller_nip when present on the new invoice

       Covers:
         a. KSeF invoice + email/PDF without KSeF number (cross-source)
         b. Two manual EU invoices with NIP (both without KSeF)
         c. Two manual non-EU invoices without NIP

    4. Missing invoice_number, issue_date, or net_amount → skip
  """

  import Ecto.Query

  alias KsefHub.Invoices.Invoice
  alias KsefHub.Repo

  @doc """
  Enriches attrs with `duplicate_of_id` and `duplicate_status` when a duplicate is found.
  Returns attrs unchanged when no duplicate is detected.
  """
  @spec detect(Ecto.UUID.t(), map()) :: map()
  def detect(company_id, attrs) do
    case find_original_id(company_id, attrs) do
      nil ->
        attrs

      original_id ->
        Map.merge(attrs, %{duplicate_of_id: original_id, duplicate_status: :suspected})
    end
  end

  @doc """
  Returns the ID of the original invoice that the given attrs would be a duplicate of.
  Returns nil when no duplicate is found.
  """
  @spec find_original_id(Ecto.UUID.t(), map(), keyword()) :: Ecto.UUID.t() | nil
  def find_original_id(company_id, attrs, opts \\ []) do
    find_by_ksef_number(company_id, attrs, opts) ||
      find_by_business_fields(company_id, attrs, opts)
  end

  # Step 1: exact KSeF number match.
  @spec find_by_ksef_number(Ecto.UUID.t(), map(), keyword()) :: Ecto.UUID.t() | nil
  defp find_by_ksef_number(company_id, attrs, opts) do
    ksef_number = attr(attrs, :ksef_number)

    if present?(ksef_number) do
      Invoice
      |> where([i], i.company_id == ^company_id)
      |> where([i], i.ksef_number == ^ksef_number)
      |> where([i], is_nil(i.duplicate_of_id))
      |> maybe_exclude_id(opts[:exclude_id])
      |> select([i], i.id)
      |> Repo.one()
    end
  end

  # Steps 2-4: business field matching.
  @spec find_by_business_fields(Ecto.UUID.t(), map(), keyword()) :: Ecto.UUID.t() | nil
  defp find_by_business_fields(company_id, attrs, opts) do
    invoice_number = attr(attrs, :invoice_number)
    issue_date = attr(attrs, :issue_date)
    net_amount = attr(attrs, :net_amount)
    seller_nip = attr(attrs, :seller_nip)
    has_ksef = present?(attr(attrs, :ksef_number))

    with true <- present?(invoice_number),
         {:ok, issue_date} <- cast_date(issue_date),
         {:ok, net_amount} <- cast_decimal(net_amount) do
      Invoice
      |> where([i], i.company_id == ^company_id)
      |> where([i], i.invoice_number == ^invoice_number)
      |> where([i], i.issue_date == ^issue_date)
      |> where([i], i.net_amount == ^net_amount)
      |> where([i], is_nil(i.duplicate_of_id))
      |> maybe_exclude_id(opts[:exclude_id])
      |> maybe_require_no_ksef(has_ksef)
      |> maybe_require_seller_nip(seller_nip)
      |> select([i], i.id)
      |> limit(1)
      |> Repo.one()
    else
      _ -> nil
    end
  end

  @spec maybe_exclude_id(Ecto.Query.t(), nil | Ecto.UUID.t()) :: Ecto.Query.t()
  defp maybe_exclude_id(query, nil), do: query
  defp maybe_exclude_id(query, id), do: where(query, [i], i.id != ^id)

  # When the new invoice has a KSeF number, candidates must NOT have one.
  # Same KSeF → already caught by find_by_ksef_number.
  # Different KSeF → definitively different invoices.
  @spec maybe_require_no_ksef(Ecto.Query.t(), boolean()) :: Ecto.Query.t()
  defp maybe_require_no_ksef(query, false), do: query
  defp maybe_require_no_ksef(query, true), do: where(query, [i], is_nil(i.ksef_number))

  # EU invoices have seller_nip — require it to match.
  # Non-EU invoices (US, etc.) have no NIP — skip this filter.
  @spec maybe_require_seller_nip(Ecto.Query.t(), nil | String.t()) :: Ecto.Query.t()
  defp maybe_require_seller_nip(query, seller_nip) do
    if present?(seller_nip),
      do: where(query, [i], i.seller_nip == ^seller_nip),
      else: query
  end

  @spec cast_date(term()) :: {:ok, Date.t()} | :error
  defp cast_date(%Date{} = d), do: {:ok, d}

  defp cast_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp cast_date(_), do: :error

  @spec cast_decimal(term()) :: {:ok, Decimal.t()} | :error
  defp cast_decimal(%Decimal{} = d), do: {:ok, d}
  defp cast_decimal(n) when is_integer(n), do: {:ok, Decimal.new(n)}
  defp cast_decimal(n) when is_float(n), do: {:ok, Decimal.from_float(n)}

  defp cast_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  defp cast_decimal(_), do: :error

  @spec attr(map(), atom()) :: term()
  defp attr(attrs, key), do: attrs[key] || attrs[Atom.to_string(key)]

  @spec present?(term()) :: boolean()
  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(s) when is_binary(s), do: String.trim(s) != ""
  defp present?(_), do: true
end
