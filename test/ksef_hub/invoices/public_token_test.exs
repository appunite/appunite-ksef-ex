defmodule KsefHub.Invoices.PublicTokenTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  describe "generate_public_token/1" do
    test "creates a unique base64url token" do
      invoice = insert(:invoice)

      assert {:ok, %Invoice{public_token: token}} = Invoices.generate_public_token(invoice)
      assert is_binary(token)
      assert String.length(token) > 20
      assert {:ok, _} = Base.url_decode64(token, padding: false)
    end

    test "generates different tokens for different invoices" do
      invoice1 = insert(:invoice)
      invoice2 = insert(:invoice)

      {:ok, updated1} = Invoices.generate_public_token(invoice1)
      {:ok, updated2} = Invoices.generate_public_token(invoice2)

      assert updated1.public_token != updated2.public_token
    end

    test "returns error when invoice already has a token" do
      invoice = insert(:invoice)

      {:ok, _} = Invoices.generate_public_token(invoice)
      assert {:error, :already_has_token} = Invoices.generate_public_token(invoice)
    end
  end

  describe "get_invoice_by_public_token/1" do
    test "returns invoice with preloaded associations for valid token" do
      invoice = insert(:invoice)
      {:ok, updated} = Invoices.generate_public_token(invoice)

      result = Invoices.get_invoice_by_public_token(updated.public_token)

      assert result.id == invoice.id
      assert Ecto.assoc_loaded?(result.company)
      assert Ecto.assoc_loaded?(result.category)
      assert Ecto.assoc_loaded?(result.tags)
    end

    test "returns nil for nonexistent token" do
      assert Invoices.get_invoice_by_public_token("nonexistent-token") == nil
    end

    test "returns nil for nil token" do
      assert Invoices.get_invoice_by_public_token(nil) == nil
    end
  end

  describe "ensure_public_token/1" do
    test "generates a token when none exists" do
      invoice = insert(:invoice)
      assert is_nil(invoice.public_token)

      assert {:ok, %Invoice{public_token: token}} = Invoices.ensure_public_token(invoice)
      assert is_binary(token)
    end

    test "is idempotent — returns existing token without DB hit" do
      invoice = insert(:invoice)
      {:ok, with_token} = Invoices.generate_public_token(invoice)

      assert {:ok, result} = Invoices.ensure_public_token(with_token)
      assert result.public_token == with_token.public_token
    end

    test "concurrent callers converge on the same token" do
      invoice = insert(:invoice)

      # Simulate race: first call wins, second call gets :already_has_token and reloads
      {:ok, first} = Invoices.generate_public_token(invoice)
      {:ok, second} = Invoices.ensure_public_token(invoice)

      assert first.public_token == second.public_token
    end
  end
end
