defmodule KsefHub.Invitations.InvitationNotifier do
  @moduledoc """
  Delivers invitation emails via Swoosh.

  Follows the same pattern as `KsefHub.Accounts.UserNotifier` for
  confirmation and password reset emails.
  """

  import Swoosh.Email

  alias KsefHub.Mailer

  @from_email Application.compile_env(
                :ksef_hub,
                :mailer_from,
                {"KSeF Hub", "noreply@ksef-hub.com"}
              )

  @doc """
  Delivers an invitation email to the invitee.

  ## Parameters
    - `email` — the invitee's email address
    - `accept_url` — the full URL with the invitation token
    - `context` — a map with `:company_name` and `:role`
  """
  @spec deliver_invitation(String.t(), String.t(), %{company_name: String.t(), role: String.t()}) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_invitation(email, accept_url, %{company_name: company_name, role: role}) do
    deliver(email, "You've been invited to join #{company_name} on KSeF Hub", """

    ==============================

    Hi,

    You've been invited to join #{company_name} on KSeF Hub as #{role}.

    You can accept this invitation by visiting the URL below:

    #{accept_url}

    This invitation expires in 7 days. If you don't have an account yet,
    you'll be asked to sign up first.

    If you weren't expecting this invitation, please ignore this email.

    ==============================
    """)
  end

  @spec deliver(String.t(), String.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(@from_email)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
