defmodule KsefHubWeb.CoreComponents.TabsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KsefHubWeb.CoreComponents

  defp render_tabs(assigns) do
    rendered_to_string(CoreComponents.tabs(assigns))
  end

  describe "tabs/1" do
    test "renders the active tab with a dark border and dark badge" do
      html =
        render_tabs(%{
          active: :payments,
          class: nil,
          tabs: [
            %{id: :payments, label: "Payments", count: 3},
            %{id: :activity, label: "Activity", count: 12}
          ]
        })

      assert html =~ ~s(data-testid="tab-payments")
      assert html =~ ~s(aria-selected="true")
      assert html =~ "border-foreground"
    end

    test "renders count badges for tabs with an integer count" do
      html =
        render_tabs(%{
          active: :activity,
          class: nil,
          tabs: [
            %{id: :payments, label: "Payments", count: 3},
            %{id: :activity, label: "Activity", count: 12}
          ]
        })

      # Count values are rendered as the text of a badge span.
      assert html =~ ~r/<span[^>]*>\s*3\s*<\/span>/
      assert html =~ ~r/<span[^>]*>\s*12\s*<\/span>/
    end

    test "omits the count badge when count is nil" do
      html =
        render_tabs(%{
          active: :access,
          class: nil,
          tabs: [
            %{id: :access, label: "Access", count: nil}
          ]
        })

      # No badge span — the tab label stands alone.
      assert html =~ "Access"
      refute html =~ ~s(min-w-[20px])
    end

    test "marks inactive tabs with aria-selected=false and muted border" do
      html =
        render_tabs(%{
          active: :payments,
          class: nil,
          tabs: [
            %{id: :payments, label: "Payments", count: 0},
            %{id: :activity, label: "Activity", count: 0}
          ]
        })

      # Activity is inactive
      assert html =~ ~s(data-testid="tab-activity")
      assert html =~ ~s(aria-selected="false")
      assert html =~ "border-transparent"
    end

    test "dispatches select_tab via phx-click with the tab id as value" do
      html =
        render_tabs(%{
          active: :comments,
          class: nil,
          tabs: [
            %{id: :comments, label: "Comments", count: 1}
          ]
        })

      assert html =~ ~s(phx-click="select_tab")
      assert html =~ ~s(phx-value-id="comments")
      refute html =~ ~s(data-phx-link="patch")
    end

    test "tablist role is applied on the nav and role=tab on each button" do
      html =
        render_tabs(%{
          active: :payments,
          class: nil,
          tabs: [
            %{id: :payments, label: "Payments", count: 1}
          ]
        })

      assert html =~ ~s(role="tablist")
      assert html =~ ~s(role="tab")
    end

    test "merges the `class` attribute into the outer container" do
      html =
        render_tabs(%{
          active: :payments,
          class: "mb-4",
          tabs: [
            %{id: :payments, label: "Payments", count: 1}
          ]
        })

      assert html =~ ~r/<div[^>]*class="[^"]*mb-4/
    end
  end
end
