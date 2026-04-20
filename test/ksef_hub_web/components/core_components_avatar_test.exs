defmodule KsefHubWeb.CoreComponents.AvatarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KsefHubWeb.CoreComponents

  describe "avatar_initials/1" do
    test "takes the first letter of each of the first two name words, uppercased" do
      assert CoreComponents.avatar_initials(%{name: "Emil Wojtaszek"}) == "EW"
    end

    test "caps at two words even for longer names" do
      assert CoreComponents.avatar_initials(%{name: "Maciej K. Test"}) == "MK"
    end

    test "falls back to the first letter of the email when name is blank" do
      assert CoreComponents.avatar_initials(%{name: "", email: "ops@example.com"}) == "O"
    end

    test "falls back to the first letter of the email when name is nil" do
      assert CoreComponents.avatar_initials(%{name: nil, email: "ops@example.com"}) == "O"
    end

    test "returns ? when neither a name nor an email are present" do
      assert CoreComponents.avatar_initials(%{}) == "?"
    end
  end

  describe "avatar_palette/1" do
    test "returns a deterministic palette class for the same id" do
      user = %{id: "abc-123"}

      assert CoreComponents.avatar_palette(user) == CoreComponents.avatar_palette(user)
    end

    test "different ids can map to different palettes (at least some pair differs)" do
      palettes =
        for suffix <- 1..20, do: CoreComponents.avatar_palette(%{id: "user-#{suffix}"})

      assert length(Enum.uniq(palettes)) > 1
    end

    test "falls back to the neutral muted palette when no id is present" do
      assert CoreComponents.avatar_palette(%{}) == "bg-muted text-muted-foreground"
    end

    test "every returned palette is one of the five hued options" do
      known =
        MapSet.new([
          "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300",
          "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300",
          "bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300",
          "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300",
          "bg-rose-100 text-rose-800 dark:bg-rose-900/40 dark:text-rose-300"
        ])

      for suffix <- 1..20 do
        assert CoreComponents.avatar_palette(%{id: "user-#{suffix}"}) in known
      end
    end
  end

  describe "avatar/1 component" do
    test "renders initials inside a circular span with palette classes" do
      html =
        rendered_to_string(
          CoreComponents.avatar(%{
            user: %{id: "u1", name: "Ada Lovelace", email: "ada@example.com"},
            class: "size-8",
            __changed__: nil
          })
        )

      assert html =~ "AL"
      assert html =~ "rounded-full"
      assert html =~ "size-8"
    end

    test "merges a custom class alongside the palette" do
      html =
        rendered_to_string(
          CoreComponents.avatar(%{
            user: %{id: "u1", name: "Ada Lovelace", email: "ada@example.com"},
            class: "size-6 mt-0.5",
            __changed__: nil
          })
        )

      assert html =~ "size-6"
      assert html =~ "mt-0.5"
    end
  end
end
