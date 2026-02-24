defmodule KsefHub.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use KsefHub.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias KsefHub.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import KsefHub.DataCase
    end
  end

  setup tags do
    KsefHub.DataCase.setup_sandbox(tags)
    # Stub prediction mock so Oban inline jobs don't fail in unrelated tests
    Mox.stub_with(KsefHub.Predictions.Mock, KsefHub.Predictions.StubService)
    Mox.stub_with(KsefHub.Unstructured.Mock, KsefHub.Unstructured.StubService)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(KsefHub.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  Captures the token from an email-sending function.

  Use this to extract tokens from functions like `deliver_user_confirmation_instructions/2`.
  The passed-in function receives a URL-builder callback (`String.t() -> String.t()`)
  and should return `{:ok, Swoosh.Email.t()}`.

  ## Parameters

    - `fun` (`((String.t() -> String.t()) -> {:ok, Swoosh.Email.t()})`) — a
      function that receives a URL-building callback and triggers email delivery.
      The URL-building callback has the shape `String.t() -> String.t()`.

  ## Returns

    `{String.t(), Swoosh.Email.t()}` — the encoded token and the captured email

  ## Example

      {encoded_token, _} =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)
  """
  @spec extract_user_token(((String.t() -> String.t()) -> {:ok, Swoosh.Email.t()})) ::
          {String.t(), Swoosh.Email.t()}
  def extract_user_token(fun) do
    {:ok, captured} = fun.(&"[TOKEN]#{&1}[/TOKEN]")
    %{text_body: body} = captured
    [_, token_and_rest | _] = String.split(body, "[TOKEN]")
    [token | _] = String.split(token_and_rest, "[/TOKEN]")
    {token, captured}
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
