defmodule KsefHub.ActivityLog.IntegrationTest do
  @moduledoc """
  Integration tests verifying that context operations emit correct activity events.
  Uses the TestEmitter for synchronous, deterministic assertions.
  """
  use KsefHub.DataCase, async: true

  alias KsefHub.ActivityLog.Event
  alias KsefHub.ActivityLog.TestEmitter
  alias KsefHub.Companies
  alias KsefHub.Invoices
  alias KsefHub.PaymentRequests

  import KsefHub.Factory

  setup do
    TestEmitter.attach(self())
    flush_activity_events()

    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    %{user: user, company: company}
  end

  describe "invoice status changes" do
    test "approve_invoice emits status_changed event", %{user: user, company: company} do
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      {:ok, _updated} =
        Invoices.approve_invoice(invoice, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.status_changed",
                         resource_type: "invoice",
                         metadata: %{old_status: "pending", new_status: "approved"}
                       }}
    end

    test "reject_invoice emits status_changed event", %{user: user, company: company} do
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      {:ok, _updated} =
        Invoices.reject_invoice(invoice, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.status_changed",
                         metadata: %{new_status: "rejected"}
                       }}
    end

    test "reset_invoice_status emits status_changed event", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, status: :approved)

      {:ok, _updated} = Invoices.reset_invoice_status(invoice)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.status_changed",
                         metadata: %{old_status: "approved", new_status: "pending"}
                       }}
    end
  end

  describe "invoice exclusion" do
    test "exclude_invoice emits excluded event", %{company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, _updated} = Invoices.exclude_invoice(invoice)

      assert_received {:activity_event, %Event{action: "invoice.excluded"}}
    end

    test "include_invoice emits included event", %{company: company} do
      invoice = insert(:invoice, company: company, is_excluded: true)

      {:ok, _updated} = Invoices.include_invoice(invoice)

      assert_received {:activity_event, %Event{action: "invoice.included"}}
    end
  end

  describe "no-op detection" do
    test "update_invoice_note does NOT emit when note unchanged", %{company: company} do
      invoice = insert(:invoice, company: company, note: "existing note")

      {:ok, _updated} = Invoices.update_invoice_note(invoice, %{note: "existing note"})

      refute_received {:activity_event, %Event{action: "invoice.note_updated"}}
    end

    test "update_invoice_note emits when note changes", %{company: company} do
      invoice = insert(:invoice, company: company, note: "old")

      {:ok, _updated} = Invoices.update_invoice_note(invoice, %{note: "new"})

      assert_received {:activity_event, %Event{action: "invoice.note_updated"}}
    end

    test "update_billing_date does NOT emit when dates unchanged", %{company: company} do
      invoice =
        insert(:invoice,
          company: company,
          billing_date_from: ~D[2026-01-01],
          billing_date_to: ~D[2026-01-01]
        )

      {:ok, _updated} =
        Invoices.update_billing_date(invoice, %{
          billing_date_from: "2026-01-01",
          billing_date_to: "2026-01-01"
        })

      refute_received {:activity_event, %Event{action: "invoice.billing_date_changed"}}
    end

    test "set_invoice_category does NOT emit when same category", %{company: company} do
      category = insert(:category, company: company)

      invoice =
        insert(:invoice, company: company, type: :expense, category: category)

      {:ok, _updated} = Invoices.set_invoice_category(invoice, category.id)

      refute_received {:activity_event, %Event{action: "invoice.classification_changed"}}
    end

    test "set_invoice_tags does NOT emit when tags unchanged", %{company: company} do
      invoice = insert(:invoice, company: company, tags: ["a", "b"])

      {:ok, _updated} = Invoices.set_invoice_tags(invoice, ["a", "b"])

      refute_received {:activity_event, %Event{action: "invoice.classification_changed"}}
    end

    test "set_invoice_cost_line does NOT emit when same value", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, cost_line: :growth)

      {:ok, _updated} = Invoices.set_invoice_cost_line(invoice, :growth)

      refute_received {:activity_event, %Event{action: "invoice.classification_changed"}}
    end

    test "set_invoice_project_tag does NOT emit when same value", %{company: company} do
      invoice = insert(:invoice, company: company, project_tag: "Q1-2026")

      {:ok, _updated} = Invoices.set_invoice_project_tag(invoice, "Q1-2026")

      refute_received {:activity_event, %Event{action: "invoice.classification_changed"}}
    end
  end

  describe "duplicate management" do
    test "confirm_duplicate emits event", %{company: company} do
      original = insert(:invoice, company: company)

      invoice =
        insert(:invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, _updated} = Invoices.confirm_duplicate(invoice)

      assert_received {:activity_event, %Event{action: "invoice.duplicate_confirmed"}}
    end

    test "dismiss_duplicate emits event", %{company: company} do
      original = insert(:invoice, company: company)

      invoice =
        insert(:invoice,
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      {:ok, _updated} = Invoices.dismiss_duplicate(invoice)

      assert_received {:activity_event, %Event{action: "invoice.duplicate_dismissed"}}
    end
  end

  describe "bank account operations" do
    test "create_bank_account emits event", %{company: company, user: user} do
      {:ok, _account} =
        Companies.create_bank_account(
          company.id,
          %{
            currency: "PLN",
            iban: "PL12105015201000009032123698",
            label: "Main"
          },
          user_id: user.id
        )

      assert_received {:activity_event,
                       %Event{
                         action: "bank_account.created",
                         metadata: %{label: "Main", currency: "PLN"}
                       }}
    end

    test "delete_bank_account emits event", %{company: company} do
      account = insert(:company_bank_account, company: company)

      {:ok, _deleted} = Companies.delete_bank_account(account)

      assert_received {:activity_event, %Event{action: "bank_account.deleted"}}
    end
  end

  describe "team operations" do
    test "block_member emits event", %{company: company} do
      other_user = insert(:user)
      membership = insert(:membership, user: other_user, company: company, role: :reviewer)

      {:ok, _blocked} = Companies.block_member(membership)

      assert_received {:activity_event, %Event{action: "team.member_blocked"}}
    end
  end

  describe "payment request operations" do
    test "void_payment_request emits event", %{company: company, user: user} do
      pr =
        insert(:payment_request,
          company: company,
          created_by: user,
          status: :pending
        )

      {:ok, _voided} = PaymentRequests.void_payment_request(company.id, pr.id)

      assert_received {:activity_event, %Event{action: "payment_request.voided"}}
    end
  end

  # Drains any stale activity events from the process mailbox
  defp flush_activity_events do
    receive do
      {:activity_event, _} -> flush_activity_events()
    after
      0 -> :ok
    end
  end
end
