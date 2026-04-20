defmodule KsefHubWeb.InvoiceLive.ActivityTimelineTest do
  use ExUnit.Case, async: true

  alias KsefHubWeb.InvoiceLive.ActivityTimeline

  describe "icon_palette/2 — status changes" do
    test "approved status is emerald" do
      assert ActivityTimeline.icon_palette("invoice.status_changed", %{"new_status" => "approved"}) =~
               "emerald"
    end

    test "rejected status is red" do
      assert ActivityTimeline.icon_palette("invoice.status_changed", %{"new_status" => "rejected"}) =~
               "red"
    end

    test "unknown status falls through to the default branch (gray)" do
      palette = ActivityTimeline.icon_palette("invoice.status_changed", %{"new_status" => "weird"})

      assert palette =~ "muted"
    end

    test "no metadata for status_changed falls through to the default branch" do
      assert ActivityTimeline.icon_palette("invoice.status_changed", %{}) =~ "muted"
    end
  end

  describe "icon_palette/2 — prefix-based categories" do
    test "classification changes are blue" do
      assert ActivityTimeline.icon_palette("invoice.classification_changed", %{}) =~ "blue"
    end

    test "extraction events are blue" do
      assert ActivityTimeline.icon_palette("invoice.extraction_completed", %{}) =~ "blue"
    end

    test "re-extraction trigger is blue" do
      assert ActivityTimeline.icon_palette("invoice.re_extraction_triggered", %{}) =~ "blue"
    end

    test "duplicate events are amber" do
      assert ActivityTimeline.icon_palette("invoice.duplicate_detected", %{}) =~ "amber"
    end

    test "payment request events are emerald" do
      assert ActivityTimeline.icon_palette("payment_request.created", %{}) =~ "emerald"
    end
  end

  describe "icon_palette/2 — defaults" do
    test "unknown action falls back to muted" do
      assert ActivityTimeline.icon_palette("something.unknown", %{}) =~ "muted"
    end

    test "invoice.created falls back to muted (no special color)" do
      assert ActivityTimeline.icon_palette("invoice.created", %{}) =~ "muted"
    end
  end

  describe "describe_action/1" do
    test "returns static description when action is mapped" do
      assert ActivityTimeline.describe_action(%{
               action: "invoice.comment_added",
               metadata: %{}
             }) == "added a comment"
    end

    test "falls back to dynamic description for invoice.created with source" do
      assert ActivityTimeline.describe_action(%{
               action: "invoice.created",
               metadata: %{"source" => "ksef"}
             }) == "added invoice via ksef"
    end

    test "falls back to dynamic description for invoice.created without source" do
      assert ActivityTimeline.describe_action(%{
               action: "invoice.created",
               metadata: %{}
             }) == "added invoice"
    end

    test "classification_changed with old and new names" do
      assert ActivityTimeline.describe_action(%{
               action: "invoice.classification_changed",
               metadata: %{"field" => "category", "old_name" => "A", "new_name" => "B"}
             }) == "updated category from A to B"
    end

    test "unknown action uses the action-as-words fallback" do
      assert ActivityTimeline.describe_action(%{
               action: "something.odd_event",
               metadata: %{}
             }) == "something odd event"
    end
  end

  describe "humanize_field/1" do
    test "returns mapped label for known field" do
      assert ActivityTimeline.humanize_field("seller_nip") == "seller NIP"
    end

    test "falls back to space-separated words for unknown field" do
      assert ActivityTimeline.humanize_field("unknown_field_name") == "unknown field name"
    end
  end
end
