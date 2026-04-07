defmodule KsefHub.ActivityLog.IntegrationTest do
  @moduledoc """
  Integration tests verifying that context operations emit correct activity events.
  Uses the TestEmitter for synchronous, deterministic assertions.
  """
  use KsefHub.DataCase, async: true

  alias KsefHub.Accounts
  alias KsefHub.ActivityLog.Event
  alias KsefHub.ActivityLog.TestEmitter
  alias KsefHub.Companies
  alias KsefHub.Credentials
  alias KsefHub.Invitations
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
                         metadata: %{"old_status" => "pending", "new_status" => "approved"}
                       }}
    end

    test "reject_invoice emits status_changed event", %{user: user, company: company} do
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      {:ok, _updated} =
        Invoices.reject_invoice(invoice, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.status_changed",
                         metadata: %{"new_status" => "rejected"}
                       }}
    end

    test "reset_invoice_status emits status_changed event", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, status: :approved)

      {:ok, _updated} = Invoices.reset_invoice_status(invoice)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.status_changed",
                         metadata: %{"old_status" => "approved", "new_status" => "pending"}
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
                         metadata: %{"label" => "Main", "currency" => "PLN"}
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

  describe "api token operations" do
    test "create_api_token emits generated event", %{user: user, company: company} do
      {:ok, %{api_token: token}} =
        Accounts.create_api_token(user.id, company.id, %{name: "CI Token"})

      token_name = token.name

      assert_received {:activity_event,
                       %Event{
                         action: "api_token.generated",
                         resource_type: "api_token",
                         metadata: %{"token_name" => ^token_name}
                       }}
    end

    test "revoke_api_token emits revoked event", %{user: user, company: company} do
      {:ok, %{api_token: token}} =
        Accounts.create_api_token(user.id, company.id, %{name: "Revoke Me"})

      flush_activity_events()

      {:ok, _revoked} = Accounts.revoke_api_token(user.id, company.id, token.id)

      assert_received {:activity_event,
                       %Event{
                         action: "api_token.revoked",
                         resource_type: "api_token"
                       }}
    end
  end

  describe "credential operations" do
    test "deactivate_credential emits invalidated event", %{user: user, company: company} do
      credential = insert(:credential, company: company)

      {:ok, _deactivated} =
        Credentials.deactivate_credential(credential, user_id: user.id)

      assert_received {:activity_event,
                       %Event{
                         action: "credential.invalidated",
                         resource_type: "credential"
                       }}
    end
  end

  describe "invoice access operations" do
    test "grant_access emits access_granted event", %{user: user, company: company} do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      {:ok, _grant} =
        Invoices.grant_access(invoice.id, reviewer.id, user.id,
          user_id: user.id,
          actor_label: user.name
        )

      reviewer_id = reviewer.id

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.access_granted",
                         metadata: %{grantee_user_id: ^reviewer_id}
                       }}
    end

    test "revoke_access emits access_revoked event", %{user: user, company: company} do
      invoice =
        insert(:invoice, company: company, type: :expense, access_restricted: true)

      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)
      {:ok, _grant} = Invoices.grant_access(invoice.id, reviewer.id, user.id)

      flush_activity_events()

      {:ok, _revoked} =
        Invoices.revoke_access(invoice.id, reviewer.id,
          user_id: user.id,
          actor_label: user.name
        )

      reviewer_id = reviewer.id

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.access_revoked",
                         metadata: %{revoked_user_id: ^reviewer_id}
                       }}
    end
  end

  describe "membership deletion" do
    test "delete_membership emits member_removed event", %{company: company, user: user} do
      other_user = insert(:user)
      membership = insert(:membership, user: other_user, company: company, role: :reviewer)

      {:ok, _deleted} =
        Companies.delete_membership(membership, user_id: user.id, actor_label: user.name)

      other_user_id = other_user.id

      assert_received {:activity_event,
                       %Event{
                         action: "team.member_removed",
                         metadata: %{"member_user_id" => ^other_user_id}
                       }}
    end
  end

  describe "invitation operations" do
    test "create_invitation emits invitation_sent event", %{user: user, company: company} do
      {:ok, %{invitation: _invitation}} =
        Invitations.create_invitation(user.id, company.id, %{
          email: "newhire@example.com",
          role: :accountant
        })

      assert_received {:activity_event,
                       %Event{
                         action: "team.invitation_sent",
                         resource_type: "invitation",
                         metadata: %{email: "newhire@example.com", role: "accountant"}
                       }}
    end

    test "accept_invitation emits invitation_accepted event", %{user: user, company: company} do
      {:ok, %{token: raw_token}} =
        Invitations.create_invitation(user.id, company.id, %{
          email: "joiner@example.com",
          role: :reviewer
        })

      flush_activity_events()

      accepter = insert(:user, email: "joiner@example.com")
      {:ok, _result} = Invitations.accept_invitation(raw_token, accepter)

      accepter_id = accepter.id

      assert_received {:activity_event,
                       %Event{
                         action: "team.invitation_accepted",
                         user_id: ^accepter_id,
                         metadata: %{email: "joiner@example.com"}
                       }}
    end
  end

  describe "invoice creation" do
    test "create_invoice emits created event with actor_label", %{user: user, company: company} do
      attrs = %{
        company_id: company.id,
        type: :expense,
        source: :manual,
        seller_nip: "1234567890",
        seller_name: "Seller",
        buyer_nip: company.nip,
        buyer_name: company.name,
        invoice_number: "FV/2026/001",
        issue_date: ~D[2026-01-15],
        net_amount: Decimal.new("81.30"),
        gross_amount: Decimal.new("100.00"),
        created_by_id: user.id
      }

      {:ok, _invoice} = Invoices.create_invoice(attrs)

      user_label = user.name || user.email

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.created",
                         actor_label: ^user_label,
                         metadata: %{"source" => "manual"}
                       }}
    end
  end

  describe "classification changes emit events" do
    test "set_invoice_category emits classification_changed with names", %{company: company} do
      old_cat = insert(:category, company: company, name: "Operations")
      new_cat = insert(:category, company: company, name: "Growth")
      invoice = insert(:invoice, company: company, type: :expense, category: old_cat)

      {:ok, _updated} = Invoices.set_invoice_category(invoice, new_cat.id)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         metadata: %{
                           "field" => "category",
                           "old_name" => "Operations",
                           "new_name" => "Growth"
                         }
                       }}
    end

    test "set_invoice_category with nil old category includes nil old_name", %{company: company} do
      category = insert(:category, company: company, name: "Payroll")
      invoice = insert(:invoice, company: company, type: :expense, category: nil)

      {:ok, _updated} = Invoices.set_invoice_category(invoice, category.id)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         metadata: %{
                           "field" => "category",
                           "old_name" => nil,
                           "new_name" => "Payroll"
                         }
                       }}
    end

    test "clearing category includes old_name and nil new_name", %{company: company} do
      category = insert(:category, company: company, name: "Marketing")
      invoice = insert(:invoice, company: company, type: :expense, category: category)

      {:ok, _updated} = Invoices.set_invoice_category(invoice, nil)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         metadata: %{
                           "field" => "category",
                           "old_name" => "Marketing",
                           "new_name" => nil
                         }
                       }}
    end

    test "set_invoice_tags emits classification_changed", %{company: company} do
      invoice = insert(:invoice, company: company, tags: [])

      {:ok, _updated} = Invoices.set_invoice_tags(invoice, ["payroll", "q1"])

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         metadata: %{"field" => "tags"}
                       }}
    end

    test "set_invoice_cost_line emits classification_changed", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, cost_line: nil)

      {:ok, _updated} = Invoices.set_invoice_cost_line(invoice, :growth)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         metadata: %{"field" => "cost_line"}
                       }}
    end

    test "set_invoice_project_tag emits classification_changed", %{company: company} do
      invoice = insert(:invoice, company: company, project_tag: nil)

      {:ok, _updated} = Invoices.set_invoice_project_tag(invoice, "Project Alpha")

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         metadata: %{"field" => "project_tag"}
                       }}
    end
  end

  describe "payment request lifecycle" do
    test "create_payment_request emits created event", %{company: company, user: user} do
      invoice = insert(:invoice, company: company, type: :expense, status: :approved)
      bank_account = insert(:company_bank_account, company: company)

      {:ok, _pr} =
        PaymentRequests.create_payment_request(company.id, user.id, %{
          invoice_id: invoice.id,
          bank_account_id: bank_account.id,
          amount: Decimal.new("100.00"),
          currency: "PLN",
          due_date: ~D[2026-02-01],
          recipient_name: "Seller Sp. z o.o.",
          title: "FV/2026/001",
          iban: "PL61109010140000071219812874"
        })

      assert_received {:activity_event,
                       %Event{action: "payment_request.created", resource_type: "payment_request"}}
    end
  end

  describe "unblock member" do
    test "unblock_member emits member_unblocked event", %{company: company} do
      other_user = insert(:user)

      membership =
        insert(:membership, user: other_user, company: company, role: :reviewer, status: :blocked)

      {:ok, _unblocked} = Companies.unblock_member(membership)

      assert_received {:activity_event, %Event{action: "team.member_unblocked"}}
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
