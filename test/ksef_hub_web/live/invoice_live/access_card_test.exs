defmodule KsefHubWeb.InvoiceLive.AccessCardTest do
  use ExUnit.Case, async: true

  alias KsefHubWeb.InvoiceLive.AccessCard

  describe "access_summary_label/2" do
    test "returns \"Team default\" in unrestricted mode regardless of grants list" do
      assert AccessCard.access_summary_label(%{access_restricted: false}, []) == "Team default"

      assert AccessCard.access_summary_label(%{access_restricted: false}, [%{}, %{}]) ==
               "Team default"
    end

    test "returns the right pluralized count in restricted mode" do
      inv = %{access_restricted: true}
      assert AccessCard.access_summary_label(inv, []) == "No one invited"
      assert AccessCard.access_summary_label(inv, [%{}]) == "1 person has access"
      assert AccessCard.access_summary_label(inv, [%{}, %{}]) == "2 people have access"
      assert AccessCard.access_summary_label(inv, Enum.map(1..5, fn _ -> %{} end)) ==
               "5 people have access"
    end
  end

  describe "granter_label/1" do
    test "uses the name when available" do
      assert AccessCard.granter_label(%{name: "Alice", email: "a@example.com"}) == "Alice"
    end

    test "falls back to the email when name is missing" do
      assert AccessCard.granter_label(%{name: nil, email: "b@example.com"}) == "b@example.com"
    end

    test "falls back to the email when name is empty" do
      assert AccessCard.granter_label(%{name: "", email: "c@example.com"}) == "c@example.com"
    end

    test "returns em-dash for nil or NotLoaded" do
      assert AccessCard.granter_label(nil) == "—"
      assert AccessCard.granter_label(%Ecto.Association.NotLoaded{}) == "—"
    end
  end

  describe "role_palette/1 — roles are visually distinguishable" do
    test "each role returns a non-empty palette string" do
      for role <- ~w(owner admin accountant approver editor viewer)a do
        palette = AccessCard.role_palette(role)
        assert is_binary(palette)
        assert palette != ""
        refute palette == "bg-muted text-muted-foreground",
               "role #{inspect(role)} should have a distinct palette, not the neutral default"
      end
    end

    test "owner, admin, and approver now render in different colors" do
      owner = AccessCard.role_palette(:owner)
      admin = AccessCard.role_palette(:admin)
      approver = AccessCard.role_palette(:approver)

      assert owner != admin
      assert admin != approver
      assert owner != approver
    end

    test "unknown role falls back to muted" do
      assert AccessCard.role_palette(:something_weird) == "bg-muted text-muted-foreground"
    end
  end

  describe "role_label/1" do
    test "capitalizes an atom role" do
      assert AccessCard.role_label(:owner) == "Owner"
      assert AccessCard.role_label(:approver) == "Approver"
    end

    test "returns em-dash for nil" do
      assert AccessCard.role_label(nil) == "—"
    end
  end
end
