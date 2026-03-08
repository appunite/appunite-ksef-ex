defmodule KsefHubWeb.ApiTestHelpers do
  @moduledoc """
  Shared helpers for API controller and plug tests.

  Provides `create_user_with_token/2` for setting up an authenticated
  user with a company-scoped API token at any role, and `api_conn/2` for
  building an authenticated JSON request conn.
  """

  import KsefHub.Factory

  alias KsefHub.Accounts

  @doc """
  Creates a user, company, membership, and company-scoped API token for the given role.

  For non-owner roles, the user is created as owner first (required to create tokens),
  then downgraded to the target role.

  Returns `%{user, company, token, api_token}` for `:owner`,
  or `{:ok, %{user, company, token, api_token}}` for other roles.

  ## Examples

      %{token: token} = create_user_with_token(:owner)
      {:ok, %{token: token}} = create_user_with_token(:reviewer)
  """
  @spec create_user_with_token(KsefHub.Companies.Membership.role(), map()) ::
          %{
            user: Accounts.User.t(),
            company: KsefHub.Companies.Company.t(),
            token: String.t(),
            api_token: Accounts.ApiToken.t()
          }
          | {:ok,
             %{
               user: Accounts.User.t(),
               company: KsefHub.Companies.Company.t(),
               token: String.t(),
               api_token: Accounts.ApiToken.t()
             }}
          | {:error, term()}
  def create_user_with_token(role, attrs \\ %{})

  def create_user_with_token(:owner, attrs) do
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

  def create_user_with_token(role, attrs) do
    user = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
    company = insert(:company)
    membership = insert(:membership, user: user, company: company, role: :owner)

    with {:ok, result} <-
           Accounts.create_api_token(
             user.id,
             company.id,
             Map.merge(%{name: "#{role} Token"}, attrs)
           ),
         {:ok, _membership} <-
           membership |> Ecto.Changeset.change(role: role) |> KsefHub.Repo.update() do
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
