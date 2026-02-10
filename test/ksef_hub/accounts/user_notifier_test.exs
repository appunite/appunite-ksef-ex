defmodule KsefHub.Accounts.UserNotifierTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory
  import Swoosh.TestAssertions

  alias KsefHub.Accounts.UserNotifier

  describe "deliver_confirmation_instructions/2" do
    test "sends confirmation email" do
      user = insert(:user, email: "confirm@example.com")
      url = "https://example.com/users/confirm/some-token"

      {:ok, _} = UserNotifier.deliver_confirmation_instructions(user, url)

      assert_email_sent(
        to: [{"", "confirm@example.com"}],
        subject: "Confirm your KSeF Hub account"
      )
    end
  end

  describe "deliver_reset_password_instructions/2" do
    test "sends reset password email" do
      user = insert(:user, email: "reset@example.com")
      url = "https://example.com/users/reset-password/some-token"

      {:ok, _} = UserNotifier.deliver_reset_password_instructions(user, url)

      assert_email_sent(
        to: [{"", "reset@example.com"}],
        subject: "Reset your KSeF Hub password"
      )
    end
  end
end
