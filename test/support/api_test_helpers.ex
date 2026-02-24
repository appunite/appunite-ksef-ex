defmodule KsefHubWeb.ApiTestHelpers do
  @moduledoc """
  Shared helpers for API controller and plug tests.

  Provides `create_owner_with_token/1` for setting up an authenticated
  owner user with a company-scoped API token, and `api_conn/2` for
  building an authenticated JSON request conn.
  """

  import KsefHub.Factory

  alias KsefHub.Accounts

  @doc """
  Creates a user, company, owner membership, and company-scoped API token.

  Accepts optional `attrs` merged into the token creation params.
  Returns a map with `:user`, `:company`, `:token` (plaintext), and `:api_token`.
  """
  @spec create_owner_with_token(map()) :: %{
          user: KsefHub.Accounts.User.t(),
          company: KsefHub.Companies.Company.t(),
          token: String.t(),
          api_token: KsefHub.Accounts.ApiToken.t()
        }
  def create_owner_with_token(attrs \\ %{}) do
    user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    {:ok, result} =
      Accounts.create_api_token(
        user.id,
        company.id,
        Map.merge(%{name: "API Token"}, attrs)
      )

    %{user: user, company: company, token: result.token, api_token: result.api_token}
  end

  @doc """
  Creates a user, company, and company-scoped API token, then changes the
  user's membership to reviewer. Token creation requires owner role, so we
  create as owner first and downgrade afterward.
  """
  @spec create_reviewer_with_token(map()) ::
          {:ok,
           %{
             user: KsefHub.Accounts.User.t(),
             company: KsefHub.Companies.Company.t(),
             token: String.t(),
             api_token: KsefHub.Accounts.ApiToken.t()
           }}
          | {:error, term()}
  def create_reviewer_with_token(attrs \\ %{}) do
    user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
    company = insert(:company)
    membership = insert(:membership, user: user, company: company, role: :owner)

    with {:ok, result} <-
           Accounts.create_api_token(
             user.id,
             company.id,
             Map.merge(%{name: "Reviewer Token"}, attrs)
           ),
         {:ok, _membership} <-
           membership |> Ecto.Changeset.change(role: :reviewer) |> KsefHub.Repo.update() do
      {:ok, %{user: user, company: company, token: result.token, api_token: result.api_token}}
    end
  end

  @doc """
  Builds a conn with Bearer authorization, JSON accept, and content-type headers.
  """
  @spec api_conn(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def api_conn(conn, token) do
    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end
end
