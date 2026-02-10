defmodule KsefHub.KsefClient.AuthWorkerTest do
  use KsefHub.DataCase, async: false

  import Mox

  import KsefHub.Factory

  alias KsefHub.Credentials
  alias KsefHub.Credentials.Encryption
  alias KsefHub.KsefClient.{AuthWorker, TokenManager}

  setup :verify_on_exit!

  setup do
    company = insert(:company, nip: "1234567890")
    %{company: company}
  end

  describe "perform/1" do
    test "authenticates and stores tokens on success", %{company: company} do
      {:ok, encrypted_cert} = Encryption.encrypt("cert-binary-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-password")

      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true,
          certificate_data_encrypted: encrypted_cert,
          certificate_password_encrypted: encrypted_pass
        })

      access_until = DateTime.add(DateTime.utc_now(), 900)
      refresh_until = DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)

      # Allow mock calls from TokenManager process
      {:ok, tm_pid} = TokenManager.ensure_started(company.id)
      Mox.allow(KsefHub.KsefClient.Mock, self(), tm_pid)

      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:ok, %{challenge: "test-challenge", timestamp: "2025-01-15T12:00:00Z"}}
      end)

      KsefHub.XadesSigner.Mock
      |> expect(:sign_challenge, fn "test-challenge",
                                    "1234567890",
                                    "cert-binary-data",
                                    "cert-password" ->
        {:ok, "<SignedXML/>"}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:authenticate_xades, fn "<SignedXML/>" ->
        {:ok, %{reference_number: "ref-1", operation_token: "op-tok-1"}}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:poll_auth_status, fn "ref-1", "op-tok-1" ->
        {:ok, :success}
      end)

      KsefHub.KsefClient.Mock
      |> expect(:redeem_tokens, fn "op-tok-1" ->
        {:ok,
         %{
           access_token: "new-access",
           refresh_token: "new-refresh",
           access_valid_until: access_until,
           refresh_valid_until: refresh_until
         }}
      end)

      assert :ok = AuthWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})

      # Verify tokens are stored in TokenManager
      assert {:ok, "new-access"} = TokenManager.ensure_access_token(company.id)
    end

    test "cancels when no active credential exists", %{company: company} do
      assert {:cancel, :no_credential} =
               AuthWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})
    end

    test "returns error when authentication fails for Oban retry", %{company: company} do
      {:ok, encrypted_cert} = Encryption.encrypt("cert-data")
      {:ok, encrypted_pass} = Encryption.encrypt("cert-pass")

      {:ok, _cred} =
        Credentials.create_credential(%{
          nip: company.nip,
          company_id: company.id,
          is_active: true,
          certificate_data_encrypted: encrypted_cert,
          certificate_password_encrypted: encrypted_pass
        })

      KsefHub.KsefClient.Mock
      |> expect(:get_challenge, fn ->
        {:error, {:ksef_error, 500, "Internal Server Error"}}
      end)

      assert {:error, {:ksef_error, 500, "Internal Server Error"}} =
               AuthWorker.perform(%Oban.Job{args: %{"company_id" => company.id}})
    end
  end
end
