defmodule KsefHub.ActivityLog.EventsTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.ActivityLog.{Event, Events, TestEmitter}

  import KsefHub.Factory

  setup do
    TestEmitter.attach(self())
    company = insert(:company)
    user = insert(:user)
    %{company: company, user: user}
  end

  describe "invoice events" do
    test "invoice_created/2 emits event with source", %{company: company, user: user} do
      invoice = build_invoice(company)

      Events.invoice_created(invoice, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.created",
                         resource_type: "invoice",
                         resource_id: resource_id,
                         company_id: company_id,
                         metadata: %{source: "ksef"}
                       }}

      assert resource_id == invoice.id
      assert company_id == company.id
    end

    test "invoice_status_changed/4 includes old and new status", %{
      company: company,
      user: user
    } do
      invoice = build_invoice(company)

      Events.invoice_status_changed(invoice, :pending, :approved,
        user_id: user.id,
        actor_label: user.name
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.status_changed",
                         metadata: %{old_status: "pending", new_status: "approved"}
                       }}
    end

    test "invoice_classification_changed/3 records changes with system actor", %{
      company: company
    } do
      invoice = build_invoice(company)

      Events.invoice_classification_changed(
        invoice,
        %{category: "office:supplies", old_category: nil},
        actor_type: "system",
        actor_label: "Auto-classifier"
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         actor_type: "system",
                         actor_label: "Auto-classifier",
                         metadata: %{category: "office:supplies"}
                       }}
    end

    test "invoice_comment_added/3 includes comment_id", %{company: company, user: user} do
      invoice = build_invoice(company)
      comment_id = Ecto.UUID.generate()

      Events.invoice_comment_added(invoice, %{id: comment_id},
        user_id: user.id,
        actor_label: user.name
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.comment_added",
                         metadata: %{comment_id: ^comment_id}
                       }}
    end

    test "invoice_access_changed/3 includes change_type", %{company: company, user: user} do
      invoice = build_invoice(company)

      Events.invoice_access_changed(invoice, "restricted",
        user_id: user.id,
        actor_label: user.name
      )

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.access_changed",
                         metadata: %{change_type: "restricted"}
                       }}
    end

    test "no event emitted when emit is not called" do
      refute_received {:activity_event, _}
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

    test "api_token_generated/2 includes token name", %{company: company, user: user} do
      token = %{id: Ecto.UUID.generate(), name: "CI Token", company_id: company.id}

      Events.api_token_generated(token, user_id: user.id, actor_label: user.name)

      assert_received {:activity_event,
                       %Event{
                         action: "api_token.generated",
                         metadata: %{token_name: "CI Token"}
                       }}
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
  end

  describe "emit/1 dispatches through configured emitter" do
    test "event struct is sent to test process" do
      event = %Event{action: "test.action", actor_type: "user", metadata: %{}}
      Events.emit(event)

      assert_received {:activity_event, ^event}
    end
  end

  defp build_invoice(company) do
    %{
      id: Ecto.UUID.generate(),
      company_id: company.id,
      source: :ksef,
      extraction_status: :complete
    }
  end
end
