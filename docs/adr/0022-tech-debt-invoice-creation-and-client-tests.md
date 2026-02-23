# 0022. Tech Debt: Invoice Creation Pattern and HTTP Client Tests

Date: 2026-02-23

## Status

Proposed

## Context

During the code review of the PDF upload feature (`feat/pdf-invoice-upload`), two structural issues were identified that affect code quality but are not scoped to the PDF upload work alone. Both predate or span multiple features, so fixing them inline would create unrelated changes in a feature branch.

---

## Issue 1: Duplicated create-then-retry-as-duplicate pattern

### Where

`lib/ksef_hub/invoices.ex` — appears in both `create_manual_invoice/2` (lines 284-295) and `do_create_pdf_upload/5` (lines 356-367).

### The pattern

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

Both functions:
1. Build attrs and call `detect_duplicate/2` optimistically
2. Attempt `create_invoice/1`
3. On unique constraint violation, call `retry_as_duplicate/2`
4. On success, enqueue a prediction (with slightly different logic)

The only differences are:
- `create_manual_invoice` always calls `enqueue_prediction/1`
- `do_create_pdf_upload` conditionally calls via `maybe_enqueue_prediction/2` (only for complete extractions)

### Why it matters

If duplicate detection logic changes (e.g., new constraint columns, different retry strategy), both call sites must be updated in lockstep. The `retry_as_duplicate/2` function itself also re-enqueues predictions, adding a third place where the enqueue-after-create logic lives.

### Proposed refactoring

Extract a shared `create_invoice_with_duplicate_retry/3`:

```elixir
@spec create_invoice_with_duplicate_retry(Ecto.UUID.t(), map(), keyword()) ::
        {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
defp create_invoice_with_duplicate_retry(company_id, attrs, opts \\ []) do
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

Callers then handle prediction enqueuing in their own `{:ok, invoice}` branch:

```elixir
def create_manual_invoice(company_id, attrs) do
  attrs = Map.merge(attrs, %{source: "manual", company_id: company_id})

  with {:ok, invoice} <- create_invoice_with_duplicate_retry(company_id, attrs) do
    enqueue_prediction(invoice)
    {:ok, invoice}
  end
end
```

This also simplifies `retry_as_duplicate/2` — it no longer needs to know about prediction enqueuing.

### Scope

Affects `create_manual_invoice/2`, `do_create_pdf_upload/5`, and `retry_as_duplicate/2`. All existing tests for manual creation, PDF upload creation, and duplicate detection must still pass.

---

## Issue 2: Thin HTTP client test coverage

### Where

- `test/ksef_hub/unstructured/client_test.exs` — 2 tests (config-not-set errors only)
- `test/ksef_hub/predictions/prediction_service_test.exs` — 3 tests (same pattern)

### What's missing

Neither HTTP client has tests for:
- Successful responses (200 with valid body)
- Error responses (non-200 status codes)
- Malformed responses (200 but unexpected body shape)
- Network errors (connection refused, timeout)
- Token-not-configured error (Unstructured client only)

### Why it's acceptable today

The behaviour + Mox pattern means **all business logic is tested** through context-level tests and controller tests. The Mox expectations in those tests cover the contract surface:

```elixir
# Context test verifies extraction mapping
Mox.expect(KsefHub.Unstructured.Mock, :extract, fn _pdf, _opts ->
  {:ok, %{"seller_nip" => "1234567890", ...}}
end)

# Controller test verifies error handling
Mox.expect(KsefHub.Unstructured.Mock, :extract, fn _pdf, _opts ->
  {:error, {:unstructured_service_error, 500}}
end)
```

The untested code is exclusively the HTTP transport layer: `Req.post/2` call construction, header assembly, and response pattern matching. This is low-complexity glue code.

### Why it should still be fixed

1. **Regression risk on HTTP layer changes.** If someone changes the multipart upload format, header name, or response parsing, no test catches it until integration.
2. **Symmetry.** Both clients (`PredictionService` and `Unstructured.Client`) have the same gap. Fixing one establishes the pattern for the other.
3. **Confidence in error branches.** The `{:error, {:request_failed, reason}}` and `{:error, {:invalid_payload, body}}` branches in the client are never exercised.

### Proposed approach

Use `Req.Test` (available since Req 0.4) to stub HTTP responses without a real server:

```elixir
defmodule KsefHub.Unstructured.ClientTest do
  use ExUnit.Case, async: true

  alias KsefHub.Unstructured.Client

  setup do
    Application.put_env(:ksef_hub, :unstructured_url, "http://localhost:9999")
    Application.put_env(:ksef_hub, :unstructured_api_token, "test-token")

    on_exit(fn ->
      Application.delete_env(:ksef_hub, :unstructured_url)
      Application.delete_env(:ksef_hub, :unstructured_api_token)
    end)
  end

  describe "extract/2" do
    test "returns extracted data on 200" do
      Req.Test.stub(UnstructuredExtract, fn conn ->
        Req.Test.json(conn, %{"seller_nip" => "1234567890"})
      end)

      assert {:ok, %{"seller_nip" => "1234567890"}} =
               Client.extract("pdf-bytes", plug: {Req.Test, UnstructuredExtract})
    end

    test "returns error on non-200 status" do
      Req.Test.stub(UnstructuredExtract, fn conn ->
        conn |> Plug.Conn.send_resp(500, "Internal Server Error")
      end)

      assert {:error, {:unstructured_service_error, 500}} =
               Client.extract("pdf-bytes", plug: {Req.Test, UnstructuredExtract})
    end
  end
end
```

Alternatively, if `Req.Test` is not available or the client doesn't support plug injection, use `Mox` on a lower-level HTTP behaviour or `Bypass` for a local HTTP server.

### Scope

Affects `test/ksef_hub/unstructured/client_test.exs` and `test/ksef_hub/predictions/prediction_service_test.exs`. No production code changes required — only test additions. The client modules may need a small refactor to accept a `plug:` option for testability if using `Req.Test`.

---

## Recommendation

Both issues are low-risk tech debt. Neither causes bugs today. Tackle them as:

1. **Create-then-retry dedup** — standalone refactor PR after the PDF upload feature merges and stabilizes. Estimated scope: ~50 lines changed in `invoices.ex`, all existing tests should pass without modification.
2. **HTTP client tests** — can be done independently of any feature work. Good candidate for a pairing session or onboarding task. Fixes both `PredictionService` and `Unstructured.Client` in one PR.
