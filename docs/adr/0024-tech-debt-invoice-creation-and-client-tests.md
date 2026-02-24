# 0024. Tech Debt: Invoice Creation Pattern and HTTP Client Tests

Date: 2026-02-23

## Status

Proposed

## Context

During the code review of the PDF upload feature (`feat/pdf-invoice-upload`), two structural issues were identified that affect code quality but are not scoped to the PDF upload work alone. Both predate or span multiple features, so fixing them inline would create unrelated changes in a feature branch.

### Duplicated create-then-retry-as-duplicate pattern

`lib/ksef_hub/invoices.ex` — appears in both `create_manual_invoice/2` and `do_create_pdf_upload/5`:

```elixir
case create_invoice(attrs) do
  {:ok, invoice} ->
    enqueue_prediction(invoice)  # or maybe_enqueue_prediction
    {:ok, invoice}

  {:error, %Ecto.Changeset{} = changeset} ->
    if unique_ksef_number_conflict?(changeset) do
      retry_as_duplicate(company_id, attrs)
    else
      {:error, changeset}
    end
end
```

If duplicate detection logic changes (e.g., new constraint columns, different retry strategy), both call sites must be updated in lockstep. The `retry_as_duplicate/2` function itself also re-enqueues predictions, adding a third place where the enqueue-after-create logic lives.

### Thin HTTP client test coverage

- `test/ksef_hub/unstructured/client_test.exs` — 2 tests (config-not-set errors only)
- `test/ksef_hub/predictions/prediction_service_test.exs` — 3 tests (same pattern)

Neither HTTP client has tests for successful responses, error responses, malformed responses, or network errors. The behaviour + Mox pattern covers all business logic through context and controller tests, but the HTTP transport layer itself (multipart upload format, header assembly, response parsing) is untested.

## Decision

### Extract `create_invoice_with_duplicate_retry/2`

Extract a shared private function that handles the create-then-retry pattern:

```elixir
defp create_invoice_with_duplicate_retry(company_id, attrs) do
  attrs = detect_duplicate(company_id, attrs)

  case create_invoice(attrs) do
    {:ok, invoice} ->
      {:ok, invoice}

    {:error, %Ecto.Changeset{} = changeset} ->
      if unique_ksef_number_conflict?(changeset) do
        retry_as_duplicate(company_id, attrs)
      else
        {:error, changeset}
      end
  end
end
```

Callers (`create_manual_invoice/2`, `do_create_pdf_upload/5`) handle prediction enqueuing in their own `{:ok, invoice}` branch. This also simplifies `retry_as_duplicate/2` — it no longer needs to know about prediction enqueuing.

### Add HTTP transport tests using `Req.Test`

Use `Req.Test` (available since Req 0.4) to stub HTTP responses without a real server. Cover successful responses, error status codes, malformed payloads, and network errors for both `Unstructured.Client` and `PredictionService`.

## Consequences

### Benefits

- Single source of truth for duplicate detection retry logic
- `retry_as_duplicate/2` simplified — no longer handles prediction enqueuing
- HTTP transport layer changes caught by tests before integration
- Symmetry between `PredictionService` and `Unstructured.Client` test patterns

### Trade-offs

- Create-then-retry refactor touches `create_manual_invoice/2`, `do_create_pdf_upload/5`, and `retry_as_duplicate/2` — all existing tests must still pass
- HTTP client tests may require a small refactor to accept a `plug:` option for testability
- Both changes are low-risk tech debt — neither causes bugs today

### Scope

1. **Create-then-retry dedup** — standalone refactor PR after the PDF upload feature merges and stabilizes. Estimated scope: ~50 lines changed in `invoices.ex`.
2. **HTTP client tests** — independent of any feature work. Fixes both `PredictionService` and `Unstructured.Client` in one PR. Affects `test/ksef_hub/unstructured/client_test.exs` and `test/ksef_hub/predictions/prediction_service_test.exs`.
