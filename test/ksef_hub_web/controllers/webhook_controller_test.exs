defmodule KsefHubWeb.WebhookControllerTest do
  @moduledoc """
  Tests for the Mailgun inbound email webhook controller.

  Uses async: false because tests mutate global Application env
  (mailgun_signing_key, inbound_allowed_sender_domain).
  """

  use KsefHubWeb.ConnCase, async: false

  import KsefHub.Factory
  import Mox

  alias KsefHub.Companies

  @signing_key "test-mailgun-signing-key"

  setup :verify_on_exit!

  setup do
    Application.put_env(:ksef_hub, :mailgun_signing_key, @signing_key)
    Application.put_env(:ksef_hub, :inbound_allowed_sender_domain, "appunite.com")

    company = insert(:company, nip: "1234567890")
    {:ok, %{company: company, token: token}} = Companies.enable_inbound_email(company)

    on_exit(fn ->
      Application.delete_env(:ksef_hub, :mailgun_signing_key)
      Application.delete_env(:ksef_hub, :inbound_allowed_sender_domain)
    end)

    %{company: company, inbound_token: token}
  end

  describe "POST /webhooks/mailgun/inbound" do
    test "returns 200 and enqueues processing for valid request", %{
      conn: conn,
      inbound_token: token
    } do
      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "9999999999",
           "seller_name" => "Seller",
           "buyer_nip" => "1234567890",
           "buyer_name" => "Buyer",
           "invoice_number" => "FV/2026/001",
           "issue_date" => "2026-02-25",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      params = build_valid_params(token)

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "ok"
    end

    test "returns 406 for invalid signature", %{conn: conn, inbound_token: token} do
      params =
        build_valid_params(token)
        |> Map.put("signature", "invalid-signature")

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 406)["error"] =~ "signature"
    end

    test "returns 200 and rejects email from disallowed domain", %{
      conn: conn,
      inbound_token: token
    } do
      params =
        build_valid_params(token)
        |> Map.put("sender", "attacker@evil.com")

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "discarded"
    end

    test "returns 200 and sends error for unknown company token", %{conn: conn} do
      params =
        build_valid_params_with_token("unknown1")
        |> Map.put("sender", "user@appunite.com")

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "rejected"
      assert json_response(conn, 200)["reason"] =~ "company"
    end

    test "returns 200 and sends error for zero attachments", %{conn: conn, inbound_token: token} do
      params =
        build_valid_params(token)
        |> Map.delete("attachment-1")

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "rejected"
      assert json_response(conn, 200)["reason"] =~ "attachment"
    end

    test "returns 200 and sends error for multiple attachments", %{
      conn: conn,
      inbound_token: token
    } do
      pdf = %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "invoice.pdf"
      }

      params =
        build_valid_params(token)
        |> Map.put("attachment-2", pdf)

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "rejected"
      assert json_response(conn, 200)["reason"] =~ "Multiple"
    end

    test "returns 200 and sends error for non-PDF attachment", %{
      conn: conn,
      inbound_token: token
    } do
      docx = %Plug.Upload{
        path: create_temp_file("not-a-pdf"),
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        filename: "invoice.docx"
      }

      params =
        build_valid_params(token)
        |> Map.put("attachment-1", docx)

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "rejected"
      assert json_response(conn, 200)["reason"] =~ "PDF"
    end

    test "returns 200 ok for duplicate mailgun message (idempotent)", %{
      conn: conn,
      inbound_token: token
    } do
      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "9999999999",
           "seller_name" => "Seller",
           "buyer_nip" => "1234567890",
           "buyer_name" => "Buyer",
           "invoice_number" => "FV/2026/001",
           "issue_date" => "2026-02-25",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      params =
        build_valid_params(token)
        |> Map.put("Message-Id", "<duplicate-msg-id@mailgun.org>")

      # First request succeeds
      conn1 = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn1, 200)["status"] == "ok"

      # Second request with same Message-Id also returns 200 (idempotent)
      conn2 = post(build_conn(), "/webhooks/mailgun/inbound", params)
      assert json_response(conn2, 200)["status"] == "ok"
    end

    test "accepts any sender domain when allowed_sender_domain is not configured", %{
      conn: conn,
      inbound_token: token
    } do
      Application.delete_env(:ksef_hub, :inbound_allowed_sender_domain)

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "9999999999",
           "seller_name" => "Seller",
           "buyer_nip" => "1234567890",
           "buyer_name" => "Buyer",
           "invoice_number" => "FV/2026/001",
           "issue_date" => "2026-02-25",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      params =
        build_valid_params(token)
        |> Map.put("sender", "user@any-domain.com")

      conn = post(conn, "/webhooks/mailgun/inbound", params)
      assert json_response(conn, 200)["status"] == "ok"
    end
  end

  # --- Helpers ---

  @spec build_valid_params(String.t()) :: map()
  defp build_valid_params(inbound_token) do
    build_valid_params_with_token(inbound_token)
  end

  @spec build_valid_params_with_token(String.t()) :: map()
  defp build_valid_params_with_token(token) do
    timestamp = "#{System.system_time(:second)}"
    mg_token = "random-mailgun-token"
    signature = compute_signature(timestamp, mg_token)

    %{
      "sender" => "user@appunite.com",
      "from" => "User <user@appunite.com>",
      "recipient" => "inv-#{token}@inbound.ksef-hub.com",
      "subject" => "Invoice FV/2026/001",
      "timestamp" => timestamp,
      "token" => mg_token,
      "signature" => signature,
      "attachment-1" => %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "invoice.pdf"
      }
    }
  end

  @spec compute_signature(String.t(), String.t()) :: String.t()
  defp compute_signature(timestamp, token) do
    :crypto.mac(:hmac, :sha256, @signing_key, "#{timestamp}#{token}")
    |> Base.encode16(case: :lower)
  end

  @spec create_temp_pdf() :: String.t()
  defp create_temp_pdf do
    create_temp_file("%PDF-1.4 test content")
  end

  @spec create_temp_file(String.t()) :: String.t()
  defp create_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "test_#{:erlang.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end
end
