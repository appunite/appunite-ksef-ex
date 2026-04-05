defmodule KsefHub.ActivityLog.EventsTest do
  @moduledoc """
  Tests for the Events module's remaining manual helpers
  (functions that can't use TrackedRepo).
  Schema-based events are tested via integration_test.exs.
  """
  use KsefHub.DataCase, async: true

  alias KsefHub.ActivityLog.{Event, Events, TestEmitter}

  import KsefHub.Factory

  setup do
    TestEmitter.attach(self())
    company = insert(:company)
    user = insert(:user)
    %{company: company, user: user}
  end

  describe "emit/1 dispatches through configured emitter" do
    test "event struct is sent to test process" do
      event = %Event{action: "test.action", actor_type: "user", metadata: %{}}
      Events.emit(event)

      assert_received {:activity_event, ^event}
    end
  end

  describe "invoice comment events" do
    test "invoice_comment_added/3 includes comment_id", %{company: company, user: user} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}
      comment_id = Ecto.UUID.generate()

      Events.invoice_comment_added(invoice_ref, %{id: comment_id},
        user_id: user.id,
        actor_label: user.name
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.comment_added",
                         metadata: %{comment_id: ^comment_id}
                       }}
    end

    test "invoice_comment_edited/3", %{company: company} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}
      comment_id = Ecto.UUID.generate()

      Events.invoice_comment_edited(invoice_ref, %{id: comment_id})

      assert_received {:activity_event, %Event{action: "invoice.comment_edited"}}
    end

    test "invoice_comment_deleted/3", %{company: company} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.invoice_comment_deleted(invoice_ref, Ecto.UUID.generate())

      assert_received {:activity_event, %Event{action: "invoice.comment_deleted"}}
    end
  end

  describe "UI-only invoice events" do
    test "invoice_public_link_generated/2", %{company: company, user: user} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.invoice_public_link_generated(invoice_ref, user_id: user.id)

      assert_received {:activity_event, %Event{action: "invoice.public_link_generated"}}
    end

    test "invoice_re_extraction_triggered/2", %{company: company} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.invoice_re_extraction_triggered(invoice_ref)

      assert_received {:activity_event, %Event{action: "invoice.re_extraction_triggered"}}
    end
  end

  describe "platform events" do
    test "sync_completed/3 uses system actor", %{company: company} do
      Events.sync_completed(company.id, %{income: 5, expense: 3})

      assert_received {:activity_event,
                       %Event{
                         action: "sync.completed",
                         actor_type: "system",
                         actor_label: "KSeF Sync",
                         metadata: %{income: 5}
                       }}
    end

    test "sync_triggered/2", %{company: company, user: user} do
      Events.sync_triggered(company.id, user_id: user.id)

      assert_received {:activity_event, %Event{action: "sync.triggered"}}
    end

    test "credential_uploaded/2", %{company: company} do
      cred = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.credential_uploaded(cred)

      assert_received {:activity_event, %Event{action: "credential.uploaded"}}
    end

    test "export_created/2", %{company: company, user: user} do
      batch = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.export_created(batch, user_id: user.id)

      assert_received {:activity_event, %Event{action: "export.created"}}
    end

    test "user_logged_in/2 sets user_id and ip_address", %{user: user} do
      Events.user_logged_in(user, ip_address: "1.2.3.4")

      assert_received {:activity_event,
                       %Event{
                         action: "user.logged_in",
                         user_id: user_id,
                         ip_address: "1.2.3.4"
                       }}

      assert user_id == user.id
    end

    test "user_logged_out/2", %{user: user} do
      Events.user_logged_out(user)

      assert_received {:activity_event, %Event{action: "user.logged_out"}}
    end
  end

  describe "invoice access events" do
    test "invoice_access_granted/3 includes grantee_user_id", %{company: company, user: user} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}
      grantee_id = Ecto.UUID.generate()

      Events.invoice_access_granted(invoice_ref, grantee_id,
        user_id: user.id,
        actor_label: user.name
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.access_granted",
                         resource_type: "invoice",
                         metadata: %{grantee_user_id: ^grantee_id}
                       }}
    end

    test "invoice_access_revoked/3 includes revoked_user_id", %{company: company, user: user} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}
      revoked_id = Ecto.UUID.generate()

      Events.invoice_access_revoked(invoice_ref, revoked_id,
        user_id: user.id,
        actor_label: user.name
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.access_revoked",
                         metadata: %{revoked_user_id: ^revoked_id}
                       }}
    end
  end

  describe "invoice download events" do
    test "invoice_downloaded/3 includes format", %{company: company, user: user} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.invoice_downloaded(invoice_ref, "pdf", user_id: user.id)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.downloaded",
                         resource_type: "invoice",
                         metadata: %{format: "pdf"}
                       }}
    end

    test "invoice_downloaded/3 with api actor_type", %{company: company} do
      invoice_ref = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.invoice_downloaded(invoice_ref, "xml",
        actor_type: "api",
        actor_label: "API: My Token"
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.downloaded",
                         actor_type: "api",
                         actor_label: "API: My Token",
                         metadata: %{format: "xml"}
                       }}
    end
  end

  describe "export download events" do
    test "export_downloaded/2", %{company: company, user: user} do
      batch = %{id: Ecto.UUID.generate(), company_id: company.id}

      Events.export_downloaded(batch, user_id: user.id)

      assert_received {:activity_event,
                       %Event{
                         action: "export.downloaded",
                         resource_type: "export"
                       }}
    end
  end

  describe "invitation events" do
    test "invitation_sent/3 includes email and role", %{company: company, user: user} do
      invitation = %{
        id: Ecto.UUID.generate(),
        company_id: company.id,
        role: :accountant
      }

      Events.invitation_sent(invitation, "new@example.com", user_id: user.id)

      assert_received {:activity_event,
                       %Event{
                         action: "team.invitation_sent",
                         resource_type: "invitation",
                         metadata: %{email: "new@example.com", role: "accountant"}
                       }}
    end

    test "invitation_accepted/3 sets actor from accepting user", %{company: company} do
      user = insert(:user, name: "Accepter")

      invitation = %{
        id: Ecto.UUID.generate(),
        company_id: company.id,
        email: "accepter@example.com",
        role: :reviewer
      }

      Events.invitation_accepted(invitation, user)

      user_id = user.id

      assert_received {:activity_event,
                       %Event{
                         action: "team.invitation_accepted",
                         user_id: ^user_id,
                         actor_label: "Accepter",
                         metadata: %{email: "accepter@example.com", role: "reviewer"}
                       }}
    end
  end
end
