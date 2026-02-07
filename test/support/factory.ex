defmodule KsefHub.Factory do
  @moduledoc """
  ExMachina factory for test data generation.

  Provides factories for all core schemas used in tests. Use `insert/1,2`
  for persisted records and `params_for/1,2` for attribute maps.
  """

  use ExMachina.Ecto, repo: KsefHub.Repo

  alias KsefHub.Accounts.{ApiToken, User}
  alias KsefHub.Credentials.Credential
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

  @doc "Builds a `Credential` with a sequenced NIP and active status."
  @spec credential_factory() :: Credential.t()
  def credential_factory do
    %Credential{
      nip: sequence(:nip, &String.pad_leading("#{&1}", 10, "0")),
      certificate_subject: "CN=Test Certificate",
      is_active: true
    }
  end

  @doc "Builds an `Invoice` with default income type and sample seller/buyer data."
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
      status: "pending"
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

  @doc "Builds a `Checkpoint` with income type and current timestamp."
  @spec checkpoint_factory() :: Checkpoint.t()
  def checkpoint_factory do
    %Checkpoint{
      checkpoint_type: "income",
      last_seen_timestamp: DateTime.utc_now(),
      nip: sequence(:checkpoint_nip, &String.pad_leading("#{&1}", 10, "0"))
    }
  end
end
