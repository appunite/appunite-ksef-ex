# Testing Guide

---

## Approach: TDD

Every feature starts with a failing test:

1. **Red** — write a test that describes the desired behaviour and watch it fail
2. **Green** — write the minimum code to make it pass
3. **Refactor** — clean up while keeping tests green

Tests live in `test/`, mirroring the source structure:
- `test/ksef_hub/` — context unit tests
- `test/ksef_hub_web/` — controller and LiveView tests
- `test/support/` — factories, mocks, fixtures

---

## Test Structure

Use `describe` blocks to group tests by function, and name tests by the scenario they cover:

```elixir
defmodule KsefHub.Invoices.ParserTest do
  use ExUnit.Case, async: true

  alias KsefHub.Invoices.Parser

  describe "parse/1" do
    test "extracts seller and buyer from FA(3) XML" do
      xml = File.read!("test/support/fixtures/sample_income.xml")

      assert {:ok, invoice} = Parser.parse(xml)
      assert invoice.seller_nip == "1234567890"
      assert invoice.buyer_name == "Acme Corp"
    end

    test "returns error for invalid XML" do
      assert {:error, :invalid_xml} = Parser.parse("<not-valid>")
    end
  end
end
```

Use `async: true` on all tests that do not share process-level state (most tests should be async).

---

## Test Data: ExMachina Factories

Use factories from `test/support/factory.ex` instead of inline attribute maps. Inline attrs are only appropriate when testing validation logic (missing fields, invalid formats).

```elixir
import KsefHub.Factory

# Insert a record with sensible defaults
invoice = insert(:invoice)

# Override specific fields
invoice = insert(:invoice, status: :approved, type: :expense)

# Build attrs without inserting (for testing context create functions)
attrs = params_for(:invoice, invoice_number: "FV/2026/001")
{:ok, invoice} = Invoices.create_invoice(attrs)
```

---

## Mocking External Services: Mox

All external dependencies (KSeF API, pdf-renderer, invoice-extractor, invoice-classifier, xmlsec1) are accessed through behaviours and mocked in tests via Mox.

**Setup (already done in `test_helper.exs`):**
```elixir
Mox.defmock(KsefHub.KsefClient.Mock, for: KsefHub.KsefClient.Behaviour)
```

**In tests:**
```elixir
import Mox

# Expect a specific call (verified at end of test)
expect(KsefHub.KsefClient.Mock, :authenticate, fn _creds ->
  {:ok, %{session_token: "test-token"}}
end)

# Stub a default return for setup blocks
stub(KsefHub.KsefClient.Mock, :fetch_invoices, fn _session, _params ->
  {:ok, []}
end)
```

Use `expect/3` when the call must happen exactly N times. Use `stub/3` for background defaults in `setup` blocks. `async: true` enables concurrent test isolation via the sandbox but does not trigger Mox verification — add `setup :verify_on_exit!` to each test module that uses `expect/3` so Mox checks expectations at test exit.

---

## FA(3) XML Fixtures

Sample FA(3) XML files live in `test/support/fixtures/`. When adding new parser behaviour, add a matching fixture that covers the edge case. See `docs/fa3-xml.md` for the full fixture index and what each file covers.

---

## What to Test

**Context functions:** every public function needs at least a happy-path test and the key error paths.

**LiveView:** mount renders correctly, user events produce the right assigns and side effects, navigation works.

**Edge cases:** not found, unauthorized, invalid input, concurrent operations.

**Do not test** private functions directly — test through the public API. Do not mock the database — use the test DB via `DataCase`.
