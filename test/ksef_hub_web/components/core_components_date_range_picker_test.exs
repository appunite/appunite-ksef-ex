defmodule KsefHubWeb.CoreComponents.DateRangePickerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KsefHubWeb.CoreComponents

  defp render_picker(overrides) do
    defaults = %{
      id: "test-range",
      from_name: "filters[date_from]",
      to_name: "filters[date_to]",
      from_value: nil,
      to_value: nil,
      label: "Date range",
      size: "sm",
      field_name: nil,
      field_value: nil,
      field_options: []
    }

    render_component(
      &CoreComponents.date_range_picker/1,
      defaults |> Map.merge(overrides) |> Enum.into([])
    )
  end

  describe "date_range_picker/1 date-column selector" do
    test "renders no selector when field options are omitted" do
      html = render_picker(%{})

      refute html =~ ~s(type="radio")
    end

    test "renders one radio per option with the current value checked" do
      html =
        render_picker(%{
          field_name: "filters[date_field]",
          field_value: "sales",
          field_options: [{"Issued", "issue"}, {"Sale", "sales"}]
        })

      assert html =~ ~s(name="filters[date_field]")
      assert html =~ ~s(value="issue")
      assert html =~ ~s(value="sales")
      assert html =~ "Issued"
      assert html =~ "Sale"
      assert [_checked] = Regex.run(~r/value="sales"[^>]*checked/, html)
      refute html =~ ~r/value="issue"[^>]*checked/
    end

    test "prefixes the trigger with the column label for a non-default column" do
      html =
        render_picker(%{
          from_value: ~D[2026-09-01],
          to_value: ~D[2026-09-30],
          field_name: "filters[date_field]",
          field_value: "sales",
          field_options: [{"Issued", "issue"}, {"Sale", "sales"}]
        })

      assert html =~ "Sale ·"
      assert html =~ "Sep 1"
    end

    test "leaves the trigger unprefixed for the default column" do
      html =
        render_picker(%{
          from_value: ~D[2026-09-01],
          to_value: ~D[2026-09-30],
          field_name: "filters[date_field]",
          field_value: "issue",
          field_options: [{"Issued", "issue"}, {"Sale", "sales"}]
        })

      refute html =~ "Issued ·"
      refute html =~ "Sale ·"
    end

    test "leaves the trigger unprefixed while no range is set" do
      html =
        render_picker(%{
          field_name: "filters[date_field]",
          field_value: "sales",
          field_options: [{"Issued", "issue"}, {"Sale", "sales"}]
        })

      refute html =~ "Sale ·"
      assert html =~ "Date range"
    end
  end
end
