defmodule KsefHubWeb.Plugs.RequirePermissionTest do
  use KsefHubWeb.ConnCase, async: true

  alias KsefHubWeb.Plugs.RequirePermission

  describe "init/1" do
    test "passes through the permission" do
      assert RequirePermission.init(:create_invoice) == :create_invoice
    end
  end

  describe "call/2" do
    test "allows request when role has the permission" do
      conn =
        build_conn()
        |> assign(:current_role, :owner)
        |> RequirePermission.call(:create_invoice)

      refute conn.halted
    end

    test "allows admin for non-restricted permissions" do
      conn =
        build_conn()
        |> assign(:current_role, :admin)
        |> RequirePermission.call(:manage_tokens)

      refute conn.halted
    end

    test "returns 403 when role lacks the permission" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> Phoenix.Controller.put_format("json")
        |> assign(:current_role, :accountant)
        |> RequirePermission.call(:create_invoice)

      assert conn.halted
      assert conn.status == 403
      assert Jason.decode!(conn.resp_body) == %{"error" => "Forbidden — insufficient permissions"}
    end

    test "returns 403 when role is nil" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> Phoenix.Controller.put_format("json")
        |> assign(:current_role, nil)
        |> RequirePermission.call(:create_invoice)

      assert conn.halted
      assert conn.status == 403
    end

    test "returns 403 when current_role is not assigned" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:phoenix_format, "json")
        |> Phoenix.Controller.put_format("json")
        |> RequirePermission.call(:create_invoice)

      assert conn.halted
      assert conn.status == 403
    end
  end
end
