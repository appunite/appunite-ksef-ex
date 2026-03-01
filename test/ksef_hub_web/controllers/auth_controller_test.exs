defmodule KsefHubWeb.AuthControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts

  describe "callback/2" do
    test "creates user and sets session for verified Google email", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-test-123",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.png"
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{user: %{"email_verified" => true}}
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"
      assert get_session(conn, :user_token)
    end

    test "any verified email is allowed (no allowlist)", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-any-user",
        info: %Ueberauth.Auth.Info{
          email: "anyone@example.com",
          name: "Any User",
          image: nil
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{user: %{"email_verified" => true}}
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/invoices"
      assert get_session(conn, :user_token)
    end

    test "rejects user with nil email", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-nil-email",
        info: %Ueberauth.Auth.Info{
          email: nil,
          name: "No Email User",
          image: nil
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
      refute get_session(conn, :user_token)
    end

    test "rejects user with blank email", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-blank-email",
        info: %Ueberauth.Auth.Info{
          email: "",
          name: "Blank Email User",
          image: nil
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
      refute get_session(conn, :user_token)
    end

    test "rejects user when email_verified is nil (missing from provider)", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-nil-verified",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Nil Verified User",
          image: nil
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
      refute get_session(conn, :user_token)
    end

    test "rejects user with unverified email", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-unverified",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Unverified User",
          image: nil
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{user: %{"email_verified" => false}}
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
      refute get_session(conn, :user_token)
    end

    test "links Google account to existing email-registered user", %{conn: conn} do
      email_user = insert(:password_user, email: "link@example.com")

      auth = %Ueberauth.Auth{
        uid: "google-link-uid",
        info: %Ueberauth.Auth.Info{
          email: "link@example.com",
          name: "Linked User",
          image: nil
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{user: %{"email_verified" => true}}
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/invoices"

      # Verify the Google UID was linked to the existing user
      linked = Accounts.get_user_by_google_uid("google-link-uid")
      assert linked.id == email_user.id
    end

    test "handles ueberauth failure", %{conn: conn} do
      failure = %Ueberauth.Failure{
        errors: [%Ueberauth.Failure.Error{message: "Something went wrong"}]
      }

      conn =
        conn
        |> assign(:ueberauth_failure, failure)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication failed"
    end
  end
end
