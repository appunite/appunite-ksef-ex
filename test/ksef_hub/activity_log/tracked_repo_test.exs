defmodule KsefHub.ActivityLog.TrackedRepoTest do
  @moduledoc """
  Unit tests for TrackedRepo — verifying event emission, no-op detection,
  delete tracking, and fallback behaviour for non-Trackable schemas.
  """
  use KsefHub.DataCase, async: true

  alias KsefHub.ActivityLog.{Event, TestEmitter, TrackedRepo}
  alias KsefHub.Invoices.{Category, Invoice}

  import KsefHub.Factory

  setup do
    TestEmitter.attach(self())
    flush_activity_events()

    company = insert(:company)
    user = insert(:user)
    %{company: company, user: user}
  end

  describe "insert/2" do
    test "emits event for Trackable schema", %{company: company, user: user} do
      changeset =
        %Invoice{company_id: company.id}
        |> Invoice.changeset(%{
          type: :expense,
          source: :manual,
          seller_nip: "1234567890",
          seller_name: "Seller",
          buyer_nip: company.nip,
          buyer_name: company.name,
          invoice_number: "FV/TEST/001",
          issue_date: ~D[2026-01-15],
          net_amount: Decimal.new("81.30"),
          gross_amount: Decimal.new("100.00")
        })

      {:ok, _invoice} = TrackedRepo.insert(changeset, user_id: user.id)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.created",
                         resource_type: "invoice"
                       }}
    end

    test "does not emit on insert failure", %{company: company} do
      # Missing required fields should cause validation error
      changeset =
        %Invoice{company_id: company.id}
        |> Invoice.changeset(%{})

      {:error, _changeset} = TrackedRepo.insert(changeset)

      refute_received {:activity_event, _}
    end

    test "emits event for Category insert via Trackable", %{company: company} do
      changeset =
        %Category{company_id: company.id}
        |> Category.changeset(%{name: "Test Category", identifier: "expenses:test"})

      {:ok, _cat} = TrackedRepo.insert(changeset)

      assert_received {:activity_event, %Event{action: "category.created"}}
    end
  end

  describe "update/2" do
    test "emits event when changeset has changes", %{company: company, user: user} do
      invoice = insert(:invoice, company: company, is_excluded: false)
      flush_activity_events()

      changeset = Invoice.changeset(invoice, %{is_excluded: true})

      {:ok, _updated} =
        TrackedRepo.update(changeset, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event, %Event{action: "invoice.excluded"}}
    end

    test "merges caller metadata into Trackable-derived metadata", %{company: company} do
      invoice = insert(:invoice, company: company, is_excluded: false)
      flush_activity_events()

      changeset = Invoice.changeset(invoice, %{is_excluded: true})

      {:ok, _updated} =
        TrackedRepo.update(changeset, metadata: %{extra_info: "from context"})

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.excluded",
                         metadata: %{"extra_info" => "from context"}
                       }}
    end

    test "skips event emission on no-op (empty changes)", %{company: company} do
      invoice = insert(:invoice, company: company, note: "same")
      flush_activity_events()

      changeset = Invoice.changeset(invoice, %{note: "same"})

      {:ok, _updated} = TrackedRepo.update(changeset)

      refute_received {:activity_event, _}
    end
  end

  describe "delete/2" do
    test "emits event for Trackable schema with track_delete", %{company: company, user: user} do
      account = insert(:company_bank_account, company: company, label: "Main", currency: "PLN")

      {:ok, _deleted} =
        TrackedRepo.delete(account, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event,
                       %Event{
                         action: "bank_account.deleted",
                         resource_type: "company_bank_account",
                         metadata: metadata
                       }}

      assert metadata["label"] == "Main"
      assert metadata["currency"] == "PLN"
    end

    test "emits member_removed for membership deletion", %{company: company, user: user} do
      other = insert(:user)
      membership = insert(:membership, user: other, company: company, role: :reviewer)

      {:ok, _deleted} =
        TrackedRepo.delete(membership, user_id: user.id, actor_label: user.name)

      other_id = other.id

      assert_received {:activity_event,
                       %Event{
                         action: "team.member_removed",
                         metadata: %{"member_user_id" => ^other_id}
                       }}
    end

    test "skips event when track_delete returns :skip" do
      # Invoice track_delete returns :skip
      company = insert(:company)
      invoice = insert(:invoice, company: company)

      {:ok, _deleted} = TrackedRepo.delete(invoice)

      refute_received {:activity_event, _}
    end
  end

  @spec flush_activity_events() :: :ok
  defp flush_activity_events do
    receive do
      {:activity_event, _} -> flush_activity_events()
    after
      0 -> :ok
    end
  end
end
