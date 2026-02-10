defmodule KsefHub.Invitations do
  @moduledoc """
  The Invitations context. Manages company invitations — creating, accepting,
  cancelling, and auto-accepting invitations on sign-up.

  Invitations use a hashed-token pattern (same as API tokens): the raw token
  is returned once on creation and only the SHA-256 hash is stored in the DB.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias KsefHub.Accounts.User
  alias KsefHub.Companies
  alias KsefHub.Companies.Membership
  alias KsefHub.Invitations.Invitation
  alias KsefHub.Repo

  @token_bytes 32
  @expiry_days 7

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  @doc """
  Creates an invitation for the given company. Only owners can invite.

  Generates a secure token (returned once) and stores only the hash.
  Returns `{:ok, %{invitation: invitation, token: raw_token}}` on success.

  ## Errors
    - `{:error, :unauthorized}` — caller is not the company owner
    - `{:error, :already_member}` — invitee email already has a membership
    - `{:error, changeset}` — validation failure (e.g., duplicate pending invitation)
  """
  @spec create_invitation(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, %{invitation: Invitation.t(), token: String.t()}}
          | {:error, :unauthorized}
          | {:error, :already_member}
          | {:error, Ecto.Changeset.t()}
  def create_invitation(user_id, company_id, attrs) do
    email = normalize_email(attrs[:email] || attrs["email"] || "")

    with {:ok, _membership} <- Companies.authorize(user_id, company_id, ["owner"]),
         :ok <- check_not_already_member(company_id, email) do
      raw_token = generate_token()
      token_hash = hash_token(raw_token)

      expires_at =
        DateTime.add(DateTime.utc_now(), @expiry_days * 24 * 3600) |> DateTime.truncate(:second)

      result =
        %Invitation{
          company_id: company_id,
          invited_by_id: user_id,
          token_hash: token_hash
        }
        |> Invitation.changeset(Map.merge(attrs, %{expires_at: expires_at, status: "pending"}))
        |> Repo.insert()

      case result do
        {:ok, invitation} -> {:ok, %{invitation: invitation, token: raw_token}}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Accept
  # ---------------------------------------------------------------------------

  @doc """
  Accepts an invitation by raw token. Creates a membership for the user.

  ## Errors
    - `{:error, :not_found}` — token invalid or invitation not pending
    - `{:error, :expired}` — invitation has expired
    - `{:error, :already_member}` — user already has a membership for the company
  """
  @spec accept_invitation(String.t(), User.t()) ::
          {:ok, %{invitation: Invitation.t(), membership: Membership.t()}}
          | {:error, :not_found}
          | {:error, :expired}
          | {:error, :already_member}
  def accept_invitation(raw_token, %User{} = user) do
    token_hash = hash_token(raw_token)

    case get_pending_invitation_by_hash(token_hash) do
      nil ->
        {:error, :not_found}

      %Invitation{} = invitation ->
        if expired?(invitation) do
          {:error, :expired}
        else
          do_accept_invitation(invitation, user)
        end
    end
  end

  @spec do_accept_invitation(Invitation.t(), User.t()) ::
          {:ok, %{invitation: Invitation.t(), membership: Membership.t()}}
          | {:error, :already_member}
  defp do_accept_invitation(invitation, user) do
    if Companies.get_membership(user.id, invitation.company_id) do
      {:error, :already_member}
    else
      Multi.new()
      |> Multi.update(:invitation, Invitation.changeset(invitation, %{status: "accepted"}))
      |> Multi.insert(:membership, fn _changes ->
        %Membership{user_id: user.id, company_id: invitation.company_id}
        |> Membership.changeset(%{role: invitation.role})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{invitation: invitation, membership: membership}} ->
          {:ok, %{invitation: invitation, membership: membership}}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel
  # ---------------------------------------------------------------------------

  @doc """
  Cancels a pending invitation. Only the company owner can cancel.

  ## Errors
    - `{:error, :unauthorized}` — caller is not the company owner
    - `{:error, :not_found}` — invitation not found or not pending
  """
  @spec cancel_invitation(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Invitation.t()} | {:error, :unauthorized} | {:error, :not_found}
  def cancel_invitation(user_id, invitation_id) do
    case Repo.get(Invitation, invitation_id) do
      %Invitation{status: "pending"} = invitation ->
        case Companies.authorize(user_id, invitation.company_id, ["owner"]) do
          {:ok, _membership} ->
            invitation
            |> Invitation.changeset(%{status: "cancelled"})
            |> Repo.update()

          {:error, :unauthorized} ->
            {:error, :unauthorized}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # List
  # ---------------------------------------------------------------------------

  @doc """
  Lists all pending, non-expired invitations for a company, ordered by newest first.
  """
  @spec list_pending_invitations(Ecto.UUID.t()) :: [Invitation.t()]
  def list_pending_invitations(company_id) do
    now = DateTime.utc_now()

    Invitation
    |> where([i], i.company_id == ^company_id)
    |> where([i], i.status == "pending")
    |> where([i], i.expires_at > ^now)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Auto-accept on sign-up
  # ---------------------------------------------------------------------------

  @doc """
  Accepts all pending, non-expired invitations matching the user's email.
  Called after sign-up or Google sign-in to auto-grant company access.

  Returns `{:ok, [membership]}` with the list of created memberships.
  """
  @spec accept_pending_invitations_for_email(User.t()) :: {:ok, [Membership.t()]}
  def accept_pending_invitations_for_email(%User{} = user) do
    email = normalize_email(user.email)
    now = DateTime.utc_now()

    invitations =
      Invitation
      |> where([i], i.email == ^email)
      |> where([i], i.status == "pending")
      |> where([i], i.expires_at > ^now)
      |> Repo.all()

    memberships =
      Enum.reduce(invitations, [], fn invitation, acc ->
        case do_accept_invitation(invitation, user) do
          {:ok, %{membership: membership}} -> [membership | acc]
          {:error, _} -> acc
        end
      end)

    {:ok, Enum.reverse(memberships)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec get_pending_invitation_by_hash(String.t()) :: Invitation.t() | nil
  defp get_pending_invitation_by_hash(token_hash) do
    Invitation
    |> where([i], i.token_hash == ^token_hash and i.status == "pending")
    |> Repo.one()
  end

  @spec check_not_already_member(Ecto.UUID.t(), String.t()) :: :ok | {:error, :already_member}
  defp check_not_already_member(company_id, email) do
    user_query =
      from(u in User,
        where: u.email == ^email,
        select: u.id
      )

    membership_exists =
      from(m in Membership,
        where: m.company_id == ^company_id and m.user_id in subquery(user_query)
      )
      |> Repo.exists?()

    if membership_exists, do: {:error, :already_member}, else: :ok
  end

  @spec expired?(Invitation.t()) :: boolean()
  defp expired?(%Invitation{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  @spec generate_token() :: String.t()
  defp generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec hash_token(String.t()) :: String.t()
  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  @spec normalize_email(String.t()) :: String.t()
  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
