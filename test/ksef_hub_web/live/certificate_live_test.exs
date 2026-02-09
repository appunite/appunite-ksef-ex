defmodule KsefHubWeb.CertificateLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Credentials

  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-cert-1", email: "test@example.com", name: "Test"})

    company = insert(:company)

    conn = conn |> init_test_session(%{user_id: user.id, current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders certificate page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Certificates"
      assert html =~ "Upload New Certificate"
    end

    test "shows active credential when exists", %{conn: conn, company: company} do
      insert(:credential, company: company, nip: company.nip, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")
      assert has_element?(view, "#active-certificate")
      assert render(view) =~ company.nip
    end

    test "defaults to p12 upload mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Certificate File (.p12 / .pfx)"
    end
  end

  describe "upload mode toggle" do
    test "switches to key_crt mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      html =
        view
        |> element(~s(button[phx-value-mode="key_crt"]))
        |> render_click()

      assert html =~ "Private Key File (.key / .pem)"
      assert html =~ "Certificate File (.crt / .pem / .cer)"
      assert html =~ "Key Passphrase"
    end

    test "switches back to p12 mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-value-mode="key_crt"]))
      |> render_click()

      html =
        view
        |> element(~s(button[phx-value-mode="p12"]))
        |> render_click()

      assert html =~ "Certificate File (.p12 / .pfx)"
      refute html =~ "Private Key File"
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
    test "converts and saves credential", %{conn: conn, company: company} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, nil ->
        {:ok, %{p12_data: "fake-p12-binary", p12_password: "generated-pass"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-value-mode="key_crt"]))
      |> render_click()

      key_input = file_input(view, "form[phx-submit=save]", :private_key, [
        %{name: "test.key", content: "fake-key-data", type: "application/x-pem-file"}
      ])

      crt_input = file_input(view, "form[phx-submit=save]", :certificate_crt, [
        %{name: "test.crt", content: "fake-crt-data", type: "application/x-pem-file"}
      ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      assert render(view) =~ "Certificate uploaded successfully."
      assert Credentials.get_active_credential(company.id)
    end

    test "shows error when converter fails", %{conn: conn} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, nil ->
        {:error, {:openssl_failed, 1, "key values mismatch"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-value-mode="key_crt"]))
      |> render_click()

      key_input = file_input(view, "form[phx-submit=save]", :private_key, [
        %{name: "test.key", content: "fake-key", type: "application/x-pem-file"}
      ])

      crt_input = file_input(view, "form[phx-submit=save]", :certificate_crt, [
        %{name: "test.crt", content: "fake-crt", type: "application/x-pem-file"}
      ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      assert render(view) =~ "Certificate conversion failed"
    end

    test "shows error when files missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-value-mode="key_crt"]))
      |> render_click()

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: ""})
      |> render_submit()

      assert render(view) =~ "Please upload both private key and certificate files."
    end

    test "passes key passphrase to converter", %{conn: conn} do
      KsefHub.Credentials.Pkcs12Converter.Mock
      |> expect(:convert, fn _key, _crt, "my-secret" ->
        {:ok, %{p12_data: "fake-p12", p12_password: "generated"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element(~s(button[phx-value-mode="key_crt"]))
      |> render_click()

      key_input = file_input(view, "form[phx-submit=save]", :private_key, [
        %{name: "test.key", content: "key-data", type: "application/x-pem-file"}
      ])

      crt_input = file_input(view, "form[phx-submit=save]", :certificate_crt, [
        %{name: "test.crt", content: "crt-data", type: "application/x-pem-file"}
      ])

      render_upload(key_input, "test.key")
      render_upload(crt_input, "test.crt")

      view
      |> form("form[phx-submit=save]", credential: %{key_passphrase: "my-secret"})
      |> render_submit()

      assert render(view) =~ "Certificate uploaded successfully."
    end
  end

  describe "deactivate" do
    test "deactivates a credential", %{conn: conn, company: company} do
      cred = insert(:credential, company: company, nip: company.nip, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element("button", "Deactivate")
      |> render_click()

      updated = Credentials.get_credential!(cred.id)
      refute updated.is_active
    end
  end
end
