defmodule KsefHubWeb.CertificateLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Credentials
  alias KsefHub.Credentials.CertificateInfo

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-cert-1", email: "test@example.com", name: "Test"})

    company = insert(:company)
    insert(:membership, user: user, company: company, role: "owner")

    # Stub auth mocks so AuthWorker (inline via Oban) succeeds after certificate upload
    stub(KsefHub.KsefClient.Mock, :get_challenge, fn ->
      {:ok, %{challenge: "stub-challenge", timestamp: "2025-01-01T00:00:00Z"}}
    end)

    stub(KsefHub.XadesSigner.Mock, :sign_challenge, fn _, _, _, _ ->
      {:ok, "<StubSignedXML/>"}
    end)

    stub(KsefHub.KsefClient.Mock, :authenticate_xades, fn _ ->
      {:ok, %{reference_number: "stub-ref", operation_token: "stub-op"}}
    end)

    stub(KsefHub.KsefClient.Mock, :poll_auth_status, fn _, _ ->
      {:ok, :success}
    end)

    stub(KsefHub.KsefClient.Mock, :redeem_tokens, fn _ ->
      {:ok,
       %{
         access_token: "stub-access",
         refresh_token: "stub-refresh",
         access_valid_until: DateTime.add(DateTime.utc_now(), 900),
         refresh_valid_until: DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)
       }}
    end)

    conn = conn |> init_test_session(%{user_id: user.id, current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders certificate page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Certificates"
    end

    test "shows empty state when no certificate", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")
      assert has_element?(view, "#no-certificate")
      assert render(view) =~ "No Certificate Configured"
    end

    test "shows upload form by default when no certificate", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")
      assert has_element?(view, "#upload-form")
    end

    test "shows current certificate when user has active cert", %{conn: conn, user: user} do
      insert(:user_certificate,
        user: user,
        is_active: true,
        certificate_subject: "CN=Test Cert"
      )

      {:ok, view, _html} = live(conn, ~p"/certificates")
      assert has_element?(view, "#current-certificate")
      assert render(view) =~ "Current Certificate"
      assert render(view) =~ "CN=Test Cert"
    end

    test "hides upload form when user has active certificate", %{conn: conn, user: user} do
      insert(:user_certificate, user: user, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")
      refute has_element?(view, "#upload-form")
    end

    test "defaults to key_crt upload mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Private Key File"
    end
  end

  describe "upload mode toggle" do
    test "switches to p12 mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      html =
        view
        |> element(~s(button[phx-value-mode="p12"]))
        |> render_click()

      assert html =~ "Certificate File (.p12 / .pfx)"
      refute html =~ "Private Key File"
    end

    test "switches back to key_crt mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-value-mode="p12"]))
      |> render_click()

      html =
        view
        |> element(~s(button[phx-value-mode="key_crt"]))
        |> render_click()

      assert html =~ "Private Key File (.key / .pem)"
      assert html =~ "Certificate File (.crt / .pem / .cer)"
      assert html =~ "Key Passphrase"
    end
  end

  describe "toggle upload form" do
    test "shows upload form when Replace Certificate clicked", %{conn: conn, user: user} do
      insert(:user_certificate, user: user, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")
      refute has_element?(view, "#upload-form")

      view
      |> element(~s(button[phx-click="toggle_upload_form"]))
      |> render_click()

      assert has_element?(view, "#upload-form")
    end

    test "hides upload form when Cancel clicked", %{conn: conn, user: user} do
      insert(:user_certificate, user: user, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      # Show form
      view
      |> element(~s(button[phx-click="toggle_upload_form"]))
      |> render_click()

      assert has_element?(view, "#upload-form")

      # Hide form
      view
      |> element(~s(button[phx-click="toggle_upload_form"]))
      |> render_click()

      refute has_element?(view, "#upload-form")
    end
  end

  describe "form validation" do
    test "validates on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element("form[phx-change=validate]")
      |> render_change(%{credential: %{password: "pass"}})

      # Form should still render (validation is server-side on submit)
      assert render(view) =~ "Certificates"
    end
  end

  describe "save with key_crt mode" do
    test "converts and saves user certificate", %{conn: conn, user: user} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, nil ->
        {:ok, %{p12_data: "fake-p12-binary", p12_password: "generated-pass"}}
      end)

      CertificateInfo.Mock
      |> expect(:extract, fn "fake-p12-binary", "generated-pass" ->
        {:ok, %{subject: "CN=Test, O=TestOrg", expires_at: ~D[2026-12-31]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      key_input =
        file_input(view, "form[phx-submit=save]", :private_key, [
          %{name: "test.key", content: "fake-key-data", type: "application/x-pem-file"}
        ])

      crt_input =
        file_input(view, "form[phx-submit=save]", :certificate_crt, [
          %{name: "test.crt", content: "fake-crt-data", type: "application/x-pem-file"}
        ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      assert has_element?(view, "#flash-info", "Certificate uploaded successfully.")

      cert = Credentials.get_active_user_certificate(user.id)
      assert cert
      assert cert.certificate_subject == "CN=Test, O=TestOrg"
      assert cert.not_after == ~D[2026-12-31]
    end

    test "hides upload form after successful upload", %{conn: conn} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, nil ->
        {:ok, %{p12_data: "fake-p12", p12_password: "generated"}}
      end)

      CertificateInfo.Mock
      |> expect(:extract, fn _data, _pass ->
        {:ok, %{subject: "CN=Test", expires_at: ~D[2026-12-31]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")
      assert has_element?(view, "#upload-form")

      key_input =
        file_input(view, "form[phx-submit=save]", :private_key, [
          %{name: "test.key", content: "key-data", type: "application/x-pem-file"}
        ])

      crt_input =
        file_input(view, "form[phx-submit=save]", :certificate_crt, [
          %{name: "test.crt", content: "crt-data", type: "application/x-pem-file"}
        ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      refute has_element?(view, "#upload-form")
      assert has_element?(view, "#current-certificate")
    end

    test "shows error when converter fails", %{conn: conn} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, nil ->
        {:error, {:openssl_failed, 1}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      key_input =
        file_input(view, "form[phx-submit=save]", :private_key, [
          %{name: "test.key", content: "fake-key", type: "application/x-pem-file"}
        ])

      crt_input =
        file_input(view, "form[phx-submit=save]", :certificate_crt, [
          %{name: "test.crt", content: "fake-crt", type: "application/x-pem-file"}
        ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      assert has_element?(
               view,
               "#flash-error",
               "Invalid key passphrase or mismatched key/certificate. Please check your files and try again."
             )
    end

    test "shows error when files missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      assert has_element?(
               view,
               "#flash-error",
               "Please upload both private key and certificate files."
             )
    end

    test "passes key passphrase to converter", %{conn: conn} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, "my-secret" ->
        {:ok, %{p12_data: "fake-p12", p12_password: "generated"}}
      end)

      CertificateInfo.Mock
      |> expect(:extract, fn "fake-p12", "generated" ->
        {:ok, %{subject: "CN=Test", expires_at: ~D[2026-12-31]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      key_input =
        file_input(view, "form[phx-submit=save]", :private_key, [
          %{name: "test.key", content: "key-data", type: "application/x-pem-file"}
        ])

      crt_input =
        file_input(view, "form[phx-submit=save]", :certificate_crt, [
          %{name: "test.crt", content: "crt-data", type: "application/x-pem-file"}
        ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: "my-secret"})
      |> render_submit()

      assert has_element?(view, "#flash-info", "Certificate uploaded successfully.")
    end
  end

  describe "remove certificate" do
    test "deactivates the user certificate", %{conn: conn, user: user} do
      cert = insert(:user_certificate, user: user, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-click="remove_certificate"]))
      |> render_click()

      # Certificate should be deactivated
      reloaded = KsefHub.Repo.get!(Credentials.UserCertificate, cert.id)
      refute reloaded.is_active

      assert has_element?(view, "#no-certificate")
      refute has_element?(view, "#current-certificate")
    end
  end
end
