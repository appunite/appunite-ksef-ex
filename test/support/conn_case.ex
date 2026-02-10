defmodule KsefHubWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KsefHubWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint KsefHubWeb.Endpoint

      use KsefHubWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import KsefHubWeb.ConnCase
    end
  end

  setup tags do
    KsefHub.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Captures the token from an email-sending function.

  Delegates to `KsefHub.DataCase.extract_user_token/1`.

  ## Parameters

    - `fun` (`(String.t() -> {:ok, Swoosh.Email.t()})`) — a function that
      receives a URL-building callback and triggers email delivery

  ## Returns

    `{String.t(), Swoosh.Email.t()}` — the encoded token and the captured email
  """
  defdelegate extract_user_token(fun), to: KsefHub.DataCase

  @doc """
  Sets up a logged-in connection by generating a session token for the user.

  ## Parameters

    - `conn` (`Plug.Conn.t()`) — the test connection
    - `user` (`KsefHub.Accounts.User.t()`) — the user to log in
    - `extra_session` (`map()`) — optional extra session keys
      (e.g., `%{current_company_id: uuid}`)

  ## Returns

    `Plug.Conn.t()` — conn with `:user_token` (and any extra keys) in session
  """
  def log_in_user(conn, user, extra_session \\ %{}) do
    token = KsefHub.Accounts.generate_user_session_token(user)

    session = Map.merge(%{user_token: token}, extra_session)

    conn
    |> Phoenix.ConnTest.init_test_session(session)
  end
end
