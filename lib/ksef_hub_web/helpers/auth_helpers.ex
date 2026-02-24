defmodule KsefHubWeb.AuthHelpers do
  @moduledoc """
  Shared helpers for resolving user roles from company memberships.
  """

  alias KsefHub.Companies

  @doc """
  Resolves the role for a user within a company.

  Returns the role atom (e.g. `:owner`, `:reviewer`) or `nil` if the user
  has no membership in the given company, or if either argument is `nil`.
  """
  @spec resolve_role(Ecto.UUID.t() | nil, Ecto.UUID.t() | nil) ::
          KsefHub.Companies.Membership.role() | nil
  def resolve_role(nil, _company_id), do: nil
  def resolve_role(_user_id, nil), do: nil

  def resolve_role(user_id, company_id) do
    case Companies.get_membership(user_id, company_id) do
      %{role: role} -> role
      nil -> nil
    end
  end
end
