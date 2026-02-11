defmodule KsefHub.Factory do
  @moduledoc """
  ExMachina factory for test data generation.

  Provides factories for all core schemas used in tests. Use `insert/1,2`
  for persisted records and `params_for/1,2` for attribute maps.
  """

  use ExMachina.Ecto, repo: KsefHub.Repo

  alias KsefHub.Accounts.{ApiToken, User}
  alias KsefHub.Companies.{Company, Membership}
  alias KsefHub.Credentials.{Credential, UserCertificate}
  alias KsefHub.Invitations.Invitation
  alias KsefHub.Invoices.Invoice
  alias KsefHub.Sync.Checkpoint

  @doc "Builds a `User` with sequenced email and google_uid."
  @spec user_factory() :: User.t()
  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: "Test User",
      google_uid: sequence(:google_uid, &"google-uid-#{&1}")
    }
  end

  @doc "Builds a `User` with email/password credentials (hashed password)."
  @spec password_user_factory() :: User.t()
  def password_user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: "Test User",
      hashed_password: Bcrypt.hash_pwd_salt("valid_password123"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  @doc "Builds a `Company` with a sequenced name and NIP."
  @spec company_factory() :: Company.t()
  def company_factory do
    %Company{
      name: sequence(:company_name, &"Company #{&1}"),
      nip: sequence(:company_nip, &String.pad_leading("#{&1}", 10, "0")),
      is_active: true
    }
  end

  @doc "Builds a `Membership` linking a user to a company with a default owner role."
  @spec membership_factory() :: Membership.t()
  def membership_factory do
    %Membership{
      role: "owner",
      user: build(:user),
      company: build(:company)
    }
  end

  @doc "Builds an `ApiToken` with a sequenced name and hash, associated to a user."
  @spec api_token_factory() :: ApiToken.t()
  def api_token_factory do
    %ApiToken{
      name: sequence(:token_name, &"Token #{&1}"),
      token_hash: sequence(:token_hash, &"hash-#{&1}"),
      token_prefix: "ksef_hub_",
      is_active: true,
      created_by: build(:user)
    }
  end

  @doc "Builds a `Credential` with a sequenced NIP, active status, and associated company."
  @spec credential_factory() :: Credential.t()
  def credential_factory do
    company = build(:company)

    %Credential{
      nip: company.nip,
      is_active: true,
      company: company
    }
  end

  @doc "Builds a `UserCertificate` with encrypted placeholder data, associated to a user."
  @spec user_certificate_factory() :: UserCertificate.t()
  def user_certificate_factory do
    %UserCertificate{
      certificate_data_encrypted: "encrypted-cert-data",
      certificate_password_encrypted: "encrypted-cert-pass",
      certificate_subject: "CN=Test User, PESEL=12345678901",
      not_before: ~D[2026-01-01],
      not_after: ~D[2028-01-01],
      fingerprint: "AA:BB:CC:DD:EE:FF",
      is_active: true,
      user: build(:user)
    }
  end

  @doc "Builds an `Invitation` with a sequenced email, pending status, and 7-day expiry."
  @spec invitation_factory() :: Invitation.t()
  def invitation_factory do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    %Invitation{
      email: sequence(:invitation_email, &"invitee#{&1}@example.com"),
      role: "accountant",
      token_hash: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower),
      status: "pending",
      expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600) |> DateTime.truncate(:second),
      company: build(:company),
      invited_by: build(:user)
    }
  end

  @doc "Builds an `Invoice` with default income type, sample seller/buyer data, and associated company."
  @spec invoice_factory() :: Invoice.t()
  def invoice_factory do
    %Invoice{
      type: "income",
      seller_nip: "1234567890",
      seller_name: "Seller Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Buyer S.A.",
      invoice_number: sequence(:invoice_number, &"FV/2025/#{&1}"),
      issue_date: Date.utc_today(),
      net_amount: Decimal.new("1000.00"),
      vat_amount: Decimal.new("230.00"),
      gross_amount: Decimal.new("1230.00"),
      currency: "PLN",
      status: "pending",
      company: build(:company)
    }
  end

  @doc "Builds an `Oban.Job` configured for the sync worker queue."
  @spec sync_job_factory() :: Oban.Job.t()
  def sync_job_factory do
    %Oban.Job{
      worker: "KsefHub.Sync.SyncWorker",
      queue: "sync",
      args: %{},
      state: "available",
      inserted_at: DateTime.utc_now(),
      meta: %{}
    }
  end

  @doc "Builds a `Checkpoint` with income type, current timestamp, and associated company."
  @spec checkpoint_factory() :: Checkpoint.t()
  def checkpoint_factory do
    %Checkpoint{
      checkpoint_type: "income",
      last_seen_timestamp: DateTime.utc_now(),
      company: build(:company)
    }
  end
end
