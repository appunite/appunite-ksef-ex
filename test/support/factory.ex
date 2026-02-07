defmodule KsefHub.Factory do
  @moduledoc "ExMachina factory for test data generation."

  use ExMachina.Ecto, repo: KsefHub.Repo

  alias KsefHub.Accounts.{User, ApiToken}
  alias KsefHub.Credentials.Credential
  alias KsefHub.Invoices.Invoice
  alias KsefHub.Sync.Checkpoint

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: "Test User",
      google_uid: sequence(:google_uid, &"google-uid-#{&1}")
    }
  end

  def api_token_factory do
    %ApiToken{
      name: sequence(:token_name, &"Token #{&1}"),
      token_hash: sequence(:token_hash, &"hash-#{&1}"),
      token_prefix: "ksef_hub_",
      is_active: true,
      created_by: build(:user)
    }
  end

  def credential_factory do
    %Credential{
      nip: sequence(:nip, &String.pad_leading("#{&1}", 10, "0")),
      certificate_subject: "CN=Test Certificate",
      is_active: true
    }
  end

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

  def checkpoint_factory do
    %Checkpoint{
      checkpoint_type: "income",
      last_seen_timestamp: DateTime.utc_now(),
      nip: sequence(:checkpoint_nip, &String.pad_leading("#{&1}", 10, "0"))
    }
  end
end
