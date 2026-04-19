defmodule KsefHub.Invitations.InvitationNotifierTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.Invitations.InvitationNotifier

  describe "deliver_invitation/3" do
    test "sends email with accept URL, company name, and role" do
      assert {:ok, email} =
               InvitationNotifier.deliver_invitation(
                 "invitee@example.com",
                 "https://ksef-hub.com/invitations/accept/abc123",
                 %{company_name: "Acme Corp", role: :accountant}
               )

      assert email.to == [{"", "invitee@example.com"}]
      assert email.subject =~ "invited"

      body = email.text_body
      assert body =~ "Acme Corp"
      assert body =~ "accountant"
      assert body =~ "https://ksef-hub.com/invitations/accept/abc123"
    end

    test "includes correct role description for reviewer" do
      assert {:ok, email} =
               InvitationNotifier.deliver_invitation(
                 "reviewer@example.com",
                 "https://ksef-hub.com/invitations/accept/xyz",
                 %{company_name: "Test Co", role: :approver}
               )

      assert email.text_body =~ "approver"
    end
  end
end
