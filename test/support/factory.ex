defmodule KsefHub.Factory do
  @moduledoc """
  ExMachina factory for test data generation.

  Provides factories for all core schemas used in tests. Use `insert/1,2`
  for persisted records and `params_for/1,2` for attribute maps.
  """

  use ExMachina.Ecto, repo: KsefHub.Repo

  alias KsefHub.Accounts.{ApiToken, User}
  alias KsefHub.AuditLog
  alias KsefHub.Companies.{Company, CompanyBankAccount, Membership}
  alias KsefHub.Credentials.{Credential, UserCertificate}
  alias KsefHub.Exports.{ExportBatch, InvoiceDownload}
  alias KsefHub.Files.File, as: FileRecord
  alias KsefHub.InboundEmail.InboundEmail, as: InboundEmailRecord
  alias KsefHub.Invitations.Invitation
  alias KsefHub.Invoices.{Category, Invoice, InvoiceAccessGrant, InvoiceComment}
  alias KsefHub.PaymentRequests.PaymentRequest
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
      role: :owner,
      status: :active,
      user: build(:user),
      company: build(:company)
    }
  end

  @doc "Builds an `ApiToken` with a sequenced name and hash, associated to a user and company."
  @spec api_token_factory() :: ApiToken.t()
  def api_token_factory do
    %ApiToken{
      name: sequence(:token_name, &"Token #{&1}"),
      token_hash: sequence(:token_hash, &"hash-#{&1}"),
      token_prefix: "ksef_hub_",
      is_active: true,
      created_by: build(:user),
      company: build(:company)
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
      role: :accountant,
      token_hash: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower),
      status: :pending,
      expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600) |> DateTime.truncate(:second),
      company: build(:company),
      invited_by: build(:user)
    }
  end

  @doc "Builds an `Invoice` with default income type, sample seller/buyer data, and associated company."
  @spec invoice_factory() :: Invoice.t()
  def invoice_factory do
    %Invoice{
      type: :income,
      source: :ksef,
      seller_nip: "1234567890",
      seller_name: "Seller Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Buyer S.A.",
      xml_file:
        build(:file,
          content: File.read!("test/support/fixtures/sample_income.xml"),
          content_type: "application/xml"
        ),
      invoice_number: sequence(:invoice_number, &"FV/2025/#{&1}"),
      issue_date: Date.utc_today(),
      billing_date_from: Date.utc_today() |> Date.beginning_of_month(),
      billing_date_to: Date.utc_today() |> Date.beginning_of_month(),
      net_amount: Decimal.new("1000.00"),
      gross_amount: Decimal.new("1230.00"),
      currency: "PLN",
      expense_approval_status: :pending,
      company: build(:company)
    }
  end

  @doc "Builds a correction `Invoice` (KOR) with correction-specific fields populated."
  @spec correction_invoice_factory() :: Invoice.t()
  def correction_invoice_factory do
    %Invoice{
      type: :expense,
      source: :ksef,
      invoice_kind: :correction,
      seller_nip: "1234567890",
      seller_name: "Seller Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Buyer S.A.",
      xml_file:
        build(:file,
          content: File.read!("test/support/fixtures/sample_correction.xml"),
          content_type: "application/xml"
        ),
      invoice_number: sequence(:invoice_number, &"KOR/2026/#{&1}"),
      issue_date: Date.utc_today(),
      billing_date_from: Date.utc_today() |> Date.beginning_of_month(),
      billing_date_to: Date.utc_today() |> Date.beginning_of_month(),
      net_amount: Decimal.new("-500.00"),
      gross_amount: Decimal.new("-615.00"),
      currency: "PLN",
      expense_approval_status: :pending,
      corrected_invoice_number: "FV/2026/001",
      corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
      corrected_invoice_date: ~D[2026-04-02],
      correction_reason: "Błąd rachunkowy",
      correction_type: 1,
      company: build(:company)
    }
  end

  @doc "Builds a manual `Invoice` without xml_file, suitable for manual entry."
  @spec manual_invoice_factory() :: Invoice.t()
  def manual_invoice_factory do
    %Invoice{
      type: :expense,
      source: :manual,
      seller_nip: "1234567890",
      seller_name: "Manual Seller Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Manual Buyer S.A.",
      invoice_number: sequence(:invoice_number, &"FV/MANUAL/#{&1}"),
      issue_date: Date.utc_today(),
      billing_date_from: Date.utc_today() |> Date.beginning_of_month(),
      billing_date_to: Date.utc_today() |> Date.beginning_of_month(),
      net_amount: Decimal.new("2000.00"),
      gross_amount: Decimal.new("2460.00"),
      currency: "PLN",
      expense_approval_status: :pending,
      company: build(:company)
    }
  end

  @doc "Builds a pdf_upload `Invoice` with pdf_file and extraction_status."
  @spec pdf_upload_invoice_factory() :: Invoice.t()
  def pdf_upload_invoice_factory do
    %Invoice{
      type: :expense,
      source: :pdf_upload,
      seller_nip: "1234567890",
      seller_name: "Extracted Seller Sp. z o.o.",
      buyer_nip: "0987654321",
      buyer_name: "Extracted Buyer S.A.",
      invoice_number: sequence(:invoice_number, &"FV/PDF/#{&1}"),
      issue_date: Date.utc_today(),
      billing_date_from: Date.utc_today() |> Date.beginning_of_month(),
      billing_date_to: Date.utc_today() |> Date.beginning_of_month(),
      net_amount: Decimal.new("1000.00"),
      gross_amount: Decimal.new("1230.00"),
      currency: "PLN",
      expense_approval_status: :pending,
      pdf_file:
        build(:file,
          content: "%PDF-1.4 fake content",
          content_type: "application/pdf",
          filename: "invoice.pdf"
        ),
      extraction_status: :complete,
      original_filename: "invoice.pdf",
      company: build(:company)
    }
  end

  @doc "Builds a `Category` with sequenced name in group:target format and associated company."
  @spec category_factory() :: Category.t()
  def category_factory do
    %Category{
      identifier: sequence(:category_identifier, &"operations:category-#{&1}"),
      name: "Test Category",
      emoji: "📦",
      description: "Test category",
      sort_order: 0,
      company: build(:company)
    }
  end

  @doc "Builds an `InvoiceAccessGrant` linking a user to an invoice."
  @spec invoice_access_grant_factory() :: InvoiceAccessGrant.t()
  def invoice_access_grant_factory do
    %InvoiceAccessGrant{
      invoice: build(:invoice),
      user: build(:user),
      granted_by: build(:user)
    }
  end

  @doc "Builds an `InvoiceComment` with a default body, associated to an invoice and user."
  @spec invoice_comment_factory() :: InvoiceComment.t()
  def invoice_comment_factory do
    %InvoiceComment{
      body: "Test comment",
      invoice: build(:invoice),
      user: build(:user)
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

  @doc "Builds an `InboundEmailRecord` with default received status and associated company."
  @spec inbound_email_factory() :: InboundEmailRecord.t()
  def inbound_email_factory do
    %InboundEmailRecord{
      sender: sequence(:inbound_sender, &"sender#{&1}@example.com"),
      recipient: "inv-test1234@inbound.ksef-hub.com",
      subject: "Invoice",
      status: :received,
      mailgun_message_id: sequence(:mailgun_msg_id, &"<msg-#{&1}@mailgun.org>"),
      company: build(:company)
    }
  end

  @doc "Builds a `File` with sample text content."
  @spec file_factory() :: FileRecord.t()
  def file_factory do
    %FileRecord{
      content: "sample file content",
      content_type: "application/octet-stream",
      filename: "test-file.bin"
    }
  end

  @doc "Builds an `ExportBatch` with default pending status and date range."
  @spec export_batch_factory() :: ExportBatch.t()
  def export_batch_factory do
    %ExportBatch{
      status: :pending,
      date_from: ~D[2026-01-01],
      date_to: ~D[2026-01-31],
      invoice_type: "expense",
      only_new: false,
      user: build(:user),
      company: build(:company)
    }
  end

  @doc "Builds an `InvoiceDownload` record linking an invoice to an export batch."
  @spec invoice_download_factory() :: InvoiceDownload.t()
  def invoice_download_factory do
    %InvoiceDownload{
      downloaded_at: DateTime.utc_now(),
      invoice: build(:invoice),
      export_batch: build(:export_batch),
      user: build(:user)
    }
  end

  @doc "Builds a `PaymentRequest` with default pending status and sample data."
  @spec payment_request_factory() :: PaymentRequest.t()
  def payment_request_factory do
    %PaymentRequest{
      recipient_name: "Dostawca Sp. z o.o.",
      recipient_nip: "1234567890",
      recipient_address: %{
        street: "ul. Testowa 1",
        city: "Warszawa",
        postal_code: "00-001",
        country: "PL"
      },
      amount: Decimal.new("1230.00"),
      currency: "PLN",
      title: "Invoice FV/2026/001",
      iban: "PL61109010140000071219812874",
      status: :pending,
      company: build(:company),
      created_by: build(:user)
    }
  end

  @doc "Builds a `CompanyBankAccount` with PLN currency."
  @spec company_bank_account_factory() :: CompanyBankAccount.t()
  def company_bank_account_factory do
    %CompanyBankAccount{
      currency: "PLN",
      iban: "PL12105015201000009032123698",
      label: "Main PLN account",
      company: build(:company)
    }
  end

  @doc "Builds an `AuditLog` entry for activity log tests."
  @spec audit_log_factory() :: AuditLog.t()
  def audit_log_factory do
    %AuditLog{
      action: "invoice.created",
      resource_type: "invoice",
      resource_id: Ecto.UUID.generate(),
      actor_type: :user,
      actor_label: "Test User",
      metadata: %{},
      company: build(:company),
      user: build(:user)
    }
  end

  @doc "Builds a `Checkpoint` with income type, current timestamp, and associated company."
  @spec checkpoint_factory() :: Checkpoint.t()
  def checkpoint_factory do
    %Checkpoint{
      checkpoint_type: :income,
      last_seen_timestamp: DateTime.utc_now(),
      company: build(:company)
    }
  end
end
