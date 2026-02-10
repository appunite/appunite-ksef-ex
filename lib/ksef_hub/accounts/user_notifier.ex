defmodule KsefHub.Accounts.UserNotifier do
  @moduledoc """
  Delivers account-related emails (confirmation, password reset) via Swoosh.
  """

  import Swoosh.Email

  alias KsefHub.Mailer

  @from_email Application.compile_env(
                :ksef_hub,
                :mailer_from,
                {"KSeF Hub", "noreply@ksef-hub.com"}
              )

  @doc """
  Delivers confirmation instructions to the user's email.

  ## Parameters
    - `user` — the user struct (must have `:email`)
    - `url` — the confirmation URL containing the token
  """
  @spec deliver_confirmation_instructions(KsefHub.Accounts.User.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your KSeF Hub account", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Delivers password reset instructions to the user's email.

  ## Parameters
    - `user` — the user struct (must have `:email`)
    - `url` — the password reset URL containing the token
  """
  @spec deliver_reset_password_instructions(KsefHub.Accounts.User.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your KSeF Hub password", """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

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
