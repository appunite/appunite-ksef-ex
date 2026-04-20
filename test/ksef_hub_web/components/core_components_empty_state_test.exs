defmodule KsefHubWeb.CoreComponents.EmptyStateTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KsefHubWeb.CoreComponents

  defp render_empty_state(assigns) do
    rendered_to_string(CoreComponents.empty_state(assigns))
  end

  describe "legacy inner_block shape" do
    test "renders an icon + inline text" do
      html =
        render_empty_state(%{
          icon: "hero-arrow-down-tray",
          title: nil,
          description: nil,
          tone: :default,
          class: nil,
          action: [],
          inner_block: [%{inner_block: fn _, _ -> "No exports yet." end}],
          __changed__: nil
        })

      assert html =~ "No exports yet."
      assert html =~ "hero-arrow-down-tray"
    end
  end

  describe "rich shape (title / description / action)" do
    test "renders title, description, and action slot" do
      html =
        render_empty_state(%{
          icon: "hero-chat-bubble-oval-left",
          title: "Start the conversation",
          description: "Leave a note for your team about this invoice.",
          tone: :default,
          class: nil,
          action: [%{inner_block: fn _, _ -> "Write a comment" end}],
          inner_block: [],
          __changed__: nil
        })

      assert html =~ "Start the conversation"
      assert html =~ "Leave a note for your team"
      assert html =~ "Write a comment"
      assert html =~ "hero-chat-bubble-oval-left"
    end

    test "omits description paragraph when not provided" do
      html =
        render_empty_state(%{
          icon: "hero-document-text",
          title: "No notes yet",
          description: nil,
          tone: :default,
          class: nil,
          action: [],
          inner_block: [],
          __changed__: nil
        })

      assert html =~ "No notes yet"
      refute html =~ "<p class=\"text-xs"
    end

    test "warning tone uses amber classes for the icon chip" do
      html =
        render_empty_state(%{
          icon: "hero-exclamation-triangle",
          title: "Line items couldn't be extracted",
          description: "Retry extraction or enter items manually.",
          tone: :warning,
          class: nil,
          action: [],
          inner_block: [],
          __changed__: nil
        })

      assert html =~ "amber"
    end

    test "locked tone uses the muted/locked classes" do
      html =
        render_empty_state(%{
          icon: "hero-lock-closed",
          title: "Payments don't apply here",
          description: nil,
          tone: :locked,
          class: nil,
          action: [],
          inner_block: [],
          __changed__: nil
        })

      assert html =~ "opacity-80"
    end
  end
end
