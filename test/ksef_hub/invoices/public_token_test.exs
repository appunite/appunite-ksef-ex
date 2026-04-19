defmodule KsefHub.Invoices.PublicTokenTest do
  use KsefHub.DataCase, async: true

  import Ecto.Query
  import KsefHub.Factory

  alias KsefHub.Companies
  alias KsefHub.Invoices
  alias KsefHub.Invoices.InvoicePublicToken
  alias KsefHub.Invoices.Invoice
  alias KsefHub.Repo

  describe "ensure_public_token/2" do
    test "creates a token and returns :created for a user who has none" do
      invoice = insert(:invoice)
      user = insert(:user)

      assert {:ok, %InvoicePublicToken{} = pt, :created} =
               Invoices.ensure_public_token(invoice, user.id)

      assert pt.invoice_id == invoice.id
      assert pt.user_id == user.id
      assert is_binary(pt.token)
      assert String.length(pt.token) > 20
      assert {:ok, _} = Base.url_decode64(pt.token, padding: false)
    end

    test "token expires 30 days from creation" do
      invoice = insert(:invoice)
      user = insert(:user)

      {:ok, pt, _} = Invoices.ensure_public_token(invoice, user.id)

      diff = DateTime.diff(pt.expires_at, DateTime.utc_now(), :day)
      assert diff in 29..30
    end

    test "returns :existing and same token for second call within TTL" do
      invoice = insert(:invoice)
      user = insert(:user)

      {:ok, first, :created} = Invoices.ensure_public_token(invoice, user.id)
      {:ok, second, :existing} = Invoices.ensure_public_token(invoice, user.id)

      assert first.token == second.token
      assert first.id == second.id
    end

    test "different users get different tokens for the same invoice" do
      invoice = insert(:invoice)
      user_a = insert(:user)
      user_b = insert(:user)

      {:ok, token_a, _} = Invoices.ensure_public_token(invoice, user_a.id)
      {:ok, token_b, _} = Invoices.ensure_public_token(invoice, user_b.id)

      refute token_a.token == token_b.token
    end

    test "rotates the token when the existing one is expired and returns :created" do
      invoice = insert(:invoice)
      user = insert(:user)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      %InvoicePublicToken{}
      |> InvoicePublicToken.changeset(%{
        invoice_id: invoice.id,
        user_id: user.id,
        token: "expired_token_aaaaaaaaaaaaaaaaaaaaaaaaaaa",
        expires_at: expired_at
      })
      |> Repo.insert!()

      {:ok, new_pt, :created} = Invoices.ensure_public_token(invoice, user.id)
      refute new_pt.token == "expired_token_aaaaaaaaaaaaaaaaaaaaaaaaaaa"
      assert DateTime.compare(new_pt.expires_at, DateTime.utc_now()) == :gt
    end
  end

  describe "get_invoice_by_public_token/1" do
    test "returns invoice with all required preloads for a valid token" do
      invoice = insert(:invoice)
      user = insert(:user)
      {:ok, pt, _} = Invoices.ensure_public_token(invoice, user.id)

      result = Invoices.get_invoice_by_public_token(pt.token)

      assert %Invoice{} = result
      assert result.id == invoice.id
      assert Ecto.assoc_loaded?(result.company)
      assert Ecto.assoc_loaded?(result.category)
      assert Ecto.assoc_loaded?(result.xml_file)
      assert Ecto.assoc_loaded?(result.pdf_file)
    end

    test "returns nil for unknown token" do
      assert Invoices.get_invoice_by_public_token("nonexistent-token-aaaaaaa") == nil
    end

    test "returns nil for nil token" do
      assert Invoices.get_invoice_by_public_token(nil) == nil
    end

    test "returns nil for expired token" do
      invoice = insert(:invoice)
      user = insert(:user)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      raw_token = "expired_token_aaaaaaaaaaaaaaaaaaaaaaaaaaa"

      %InvoicePublicToken{}
      |> InvoicePublicToken.changeset(%{
        invoice_id: invoice.id,
        user_id: user.id,
        token: raw_token,
        expires_at: expired_at
      })
      |> Repo.insert!()

      assert Invoices.get_invoice_by_public_token(raw_token) == nil
    end

    test "each user's token independently resolves the same invoice" do
      invoice = insert(:invoice)
      user_a = insert(:user)
      user_b = insert(:user)

      {:ok, token_a, _} = Invoices.ensure_public_token(invoice, user_a.id)
      {:ok, token_b, _} = Invoices.ensure_public_token(invoice, user_b.id)

      assert Invoices.get_invoice_by_public_token(token_a.token).id == invoice.id
      assert Invoices.get_invoice_by_public_token(token_b.token).id == invoice.id
      refute token_a.token == token_b.token
    end

    test "deleting the invoice cascades to its public tokens" do
      invoice = insert(:invoice)
      user = insert(:user)
      {:ok, pt, _} = Invoices.ensure_public_token(invoice, user.id)

      Repo.delete!(invoice)

      assert Repo.get(InvoicePublicToken, pt.id) == nil
    end
  end

  describe "delete_public_tokens_for_user/2" do
    test "deletes all tokens for the user within the given company" do
      company = insert(:company)
      user = insert(:user)
      invoice_1 = insert(:invoice, company: company)
      invoice_2 = insert(:invoice, company: company)

      {:ok, _, _} = Invoices.ensure_public_token(invoice_1, user.id)
      {:ok, _, _} = Invoices.ensure_public_token(invoice_2, user.id)

      Invoices.delete_public_tokens_for_user(user.id, company.id)

      count =
        Repo.one(
          from pt in InvoicePublicToken,
            where: pt.user_id == ^user.id,
            select: count()
        )

      assert count == 0
    end

    test "does not delete tokens for the same user in a different company" do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user)

      invoice_a = insert(:invoice, company: company_a)
      invoice_b = insert(:invoice, company: company_b)

      {:ok, _, _} = Invoices.ensure_public_token(invoice_a, user.id)
      {:ok, pt_b, _} = Invoices.ensure_public_token(invoice_b, user.id)

      Invoices.delete_public_tokens_for_user(user.id, company_a.id)

      assert Repo.get(InvoicePublicToken, pt_b.id) != nil
    end

    test "blocking a company member invalidates their shared links" do
      company = insert(:company)
      user = insert(:user)
      membership = insert(:membership, user: user, company: company, role: :approver)
      invoice = insert(:invoice, company: company)

      {:ok, pt, _} = Invoices.ensure_public_token(invoice, user.id)
      assert Invoices.get_invoice_by_public_token(pt.token) != nil

      {:ok, _} = Companies.block_member(membership)
      Invoices.delete_public_tokens_for_user(user.id, company.id)

      assert Invoices.get_invoice_by_public_token(pt.token) == nil
    end
  end
end
