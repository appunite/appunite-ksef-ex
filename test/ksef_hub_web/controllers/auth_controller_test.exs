defmodule KsefHubWeb.AuthControllerTest do
  use KsefHubWeb.ConnCase, async: true

  alias KsefHub.Accounts

  describe "callback/2" do
    test "creates user and sets session for allowed email", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-test-123",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.png"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"
      assert get_session(conn, :user_id)
    end

    test "rejects user with disallowed email", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google-unauthorized-123",
        info: %Ueberauth.Auth.Info{
          email: "unauthorized@example.com",
          name: "Unauth User",
          image: nil
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
      refute get_session(conn, :user_id)
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

  describe "logout/2" do
    test "clears session and redirects", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_user(%{uid: "g-1", email: "test@example.com"})

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> delete("/auth/logout")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out"
    end
  end
end
