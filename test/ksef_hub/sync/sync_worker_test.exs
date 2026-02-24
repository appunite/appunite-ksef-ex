defmodule KsefHub.Sync.SyncWorkerTest do
  use KsefHub.DataCase, async: false

  import Mox

  import KsefHub.Factory

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Encryption
  alias KsefHub.KsefClient.TokenManager
  alias KsefHub.Sync.SyncWorker

  setup :verify_on_exit!

  setup do
    company = insert(:company, nip: "1234567890")
    user = insert(:user)
    insert(:membership, user: user, company: company, role: "owner")
    %{company: company, user: user}
  end

  describe "perform/1" do
    test "cancels sync when no active credential", %{company: company} do
      assert {:cancel, :no_credential} =
               SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})
    end

    test "cancels sync when no owner certificate", %{company: company} do
      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true
        })

      assert {:cancel, :no_certificate} =
               SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})
    end

    test "syncs invoices when credential, certificate, and tokens are available", %{
      company: company,
      user: user
    } do
      {:ok, encrypted_cert} = Encryption.encrypt("cert-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-pass")

      {:ok, cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true
        })

      insert(:user_certificate,
        user: user,
        certificate_data_encrypted: encrypted_cert,
        certificate_password_encrypted: encrypted_pass,
        is_active: true
      )

      # Store valid tokens via TokenManager
      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      {:ok, pid} = TokenManager.ensure_started(company.id)
      Mox.allow(KsefHub.KsefClient.Mock, self(), pid)

      :ok =
        TokenManager.store_tokens(company.id, "access-tok", "refresh-tok", future, refresh_future)

      # Mock empty query results (no invoices to sync)
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, 2, fn "access-tok", _filters, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)
      |> expect(:terminate_session, fn "access-tok" -> :ok end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})

      # Verify last_sync_at was updated
      updated = Repo.get!(Credentials.Credential, cred.id)
      assert updated.last_sync_at != nil
    end

    test "re-authenticates and syncs when token is expired", %{company: company, user: user} do
      {:ok, encrypted_cert} = Encryption.encrypt("cert-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-pass")

      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true
        })

      insert(:user_certificate,
        user: user,
        certificate_data_encrypted: encrypted_cert,
        certificate_password_encrypted: encrypted_pass,
        is_active: true
      )

      # Start TokenManager with NO tokens (will return :reauth_required)
      {:ok, pid} = TokenManager.ensure_started(company.id)
      Mox.allow(KsefHub.KsefClient.Mock, self(), pid)
      Mox.allow(KsefHub.XadesSigner.Mock, self(), pid)

      access_until = DateTime.add(DateTime.utc_now(), 900)
      refresh_until = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      # Expect XADES re-authentication flow
      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:ok, %{challenge: "reauth-challenge", timestamp: "2025-01-15T12:00:00Z"}}
      end)

      KsefHub.XadesSigner.Mock
      |> expect(:sign_challenge, fn "reauth-challenge", "1234567890", "cert-data", "cert-pass" ->
        {:ok, "<ReauthSignedXML/>"}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:authenticate_xades, fn "<ReauthSignedXML/>" ->
        {:ok,
         %{
           reference_number: "ref-reauth",
           auth_token: "auth-tok-reauth",
           auth_token_valid_until: DateTime.add(DateTime.utc_now(), 300)
         }}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:poll_auth_status, fn "ref-reauth", "auth-tok-reauth" ->
        {:ok, :success}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:redeem_tokens, fn "auth-tok-reauth" ->
        {:ok,
         %{
           access_token: "reauth-access",
           refresh_token: "reauth-refresh",
           access_valid_until: access_until,
           refresh_valid_until: refresh_until
         }}
      end)

      # After re-auth, expect sync queries with the new token
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, 2, fn "reauth-access", _filters, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)
      |> expect(:terminate_session, fn "reauth-access" -> :ok end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})
    end

    test "re-authenticates when access and refresh tokens are expired", %{
      company: company,
      user: user
    } do
      {:ok, encrypted_cert} = Encryption.encrypt("cert-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-pass")

      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true
        })

      insert(:user_certificate,
        user: user,
        certificate_data_encrypted: encrypted_cert,
        certificate_password_encrypted: encrypted_pass,
        is_active: true
      )

      # Store EXPIRED tokens (both access and refresh in the past)
      expired_access = DateTime.add(DateTime.utc_now(), -3600)
      expired_refresh = DateTime.add(DateTime.utc_now(), -60)

      {:ok, pid} = TokenManager.ensure_started(company.id)
      Mox.allow(KsefHub.KsefClient.Mock, self(), pid)
      Mox.allow(KsefHub.XadesSigner.Mock, self(), pid)

      :ok =
        TokenManager.store_tokens(
          company.id,
          "expired-access",
          "expired-refresh",
          expired_access,
          expired_refresh
        )

      access_until = DateTime.add(DateTime.utc_now(), 900)
      refresh_until = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      # Expect XADES re-authentication flow (triggered by expired tokens)
      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:ok, %{challenge: "expired-challenge", timestamp: "2025-01-15T12:00:00Z"}}
      end)

      KsefHub.XadesSigner.Mock
      |> expect(:sign_challenge, fn "expired-challenge", "1234567890", "cert-data", "cert-pass" ->
        {:ok, "<ExpiredSignedXML/>"}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:authenticate_xades, fn "<ExpiredSignedXML/>" ->
        {:ok,
         %{
           reference_number: "ref-expired",
           auth_token: "auth-tok-expired",
           auth_token_valid_until: DateTime.add(DateTime.utc_now(), 300)
         }}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:poll_auth_status, fn "ref-expired", "auth-tok-expired" ->
        {:ok, :success}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:redeem_tokens, fn "auth-tok-expired" ->
        {:ok,
         %{
           access_token: "fresh-access",
           refresh_token: "fresh-refresh",
           access_valid_until: access_until,
           refresh_valid_until: refresh_until
         }}
      end)

      # After re-auth, expect sync queries with the fresh token
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, 2, fn "fresh-access", _filters, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)
      |> expect(:terminate_session, fn "fresh-access" -> :ok end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})
    end

    test "returns retryable error when re-auth fails", %{company: company, user: user} do
      {:ok, encrypted_cert} = Encryption.encrypt("cert-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-pass")

      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true
        })

      insert(:user_certificate,
        user: user,
        certificate_data_encrypted: encrypted_cert,
        certificate_password_encrypted: encrypted_pass,
        is_active: true
      )

      # Start TokenManager with NO tokens (will return :reauth_required)
      {:ok, pid} = TokenManager.ensure_started(company.id)
      Mox.allow(KsefHub.KsefClient.Mock, self(), pid)

      # Re-auth fails
      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:error, {:ksef_error, 500, "Internal Server Error"}}
      end)

      result = SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})

      assert {:error, {:reauth_failed, {:ksef_error, 500, "Internal Server Error"}}} = result
    end

    test "downloads and upserts invoices from KSeF", %{company: company, user: user} do
      xml = File.read!("test/support/fixtures/sample_income.xml")
      {:ok, encrypted_cert} = Encryption.encrypt("cert-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-pass")

      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true
        })

      insert(:user_certificate,
        user: user,
        certificate_data_encrypted: encrypted_cert,
        certificate_password_encrypted: encrypted_pass,
        is_active: true
      )

      future = DateTime.add(DateTime.utc_now(), 600)
      refresh_future = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      {:ok, pid} = TokenManager.ensure_started(company.id)
      Mox.allow(KsefHub.KsefClient.Mock, self(), pid)

      :ok =
        TokenManager.store_tokens(company.id, "access-tok", "refresh-tok", future, refresh_future)

      storage_date = DateTime.to_iso8601(DateTime.utc_now())

      # Income query returns one invoice header
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn "access-tok", %{type: :income}, _opts ->
        {:ok,
         %{
           invoices: [
             %{
               "ksefNumber" => "KSEF-INCOME-001",
               "acquisitionDate" => storage_date,
               "permanentStorageDate" => storage_date
             }
           ],
           has_more: false,
           is_truncated: false
         }}
      end)

      # Expense query returns empty
      KsefHub.KsefClient.Mock
      |> expect(:query_invoice_metadata, fn "access-tok", %{type: :expense}, _opts ->
        {:ok, %{invoices: [], has_more: false, is_truncated: false}}
      end)

      # Download the income invoice
      KsefHub.KsefClient.Mock
      |> expect(:download_invoice, fn "access-tok", "KSEF-INCOME-001" ->
        {:ok, xml}
      end)
      |> expect(:terminate_session, fn "access-tok" -> :ok end)

      assert :ok = SyncWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})

      # Verify invoice was created
      invoice = KsefHub.Invoices.get_invoice_by_ksef_number(company.id, "KSEF-INCOME-001")
      assert invoice != nil
      assert invoice.type == :income
      assert invoice.seller_nip == "1234567890"
      assert invoice.invoice_number == "FV/2025/001"
    end
  end
end
