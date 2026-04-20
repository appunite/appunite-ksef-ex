defmodule KsefHubWeb.InvoiceLive.ActivityTimeline do
  @moduledoc """
  Vertical activity timeline for the invoice show page.

  Renders a stream of audit-log entries as a left-anchored list of circular
  icons connected by a vertical line, with the actor, action description, and
  a monospace UTC timestamp for each entry.

  The public entry point is `timeline/1`; `icon_palette/2` and
  `describe_action/1` are exposed so tests can exercise the branch logic
  without rendering a full template.
  """

  use Phoenix.Component

  import KsefHubWeb.CoreComponents, only: [icon: 1]
  import KsefHubWeb.InvoiceComponents, only: [local_datetime: 1]

  @action_icons %{
    "invoice.created" => "hero-plus-circle",
    "invoice.status_changed" => "hero-check-circle",
    "invoice.classification_changed" => "hero-tag",
    "invoice.excluded" => "hero-eye-slash",
    "invoice.included" => "hero-eye",
    "invoice.access_changed" => "hero-lock-closed",
    "invoice.public_link_generated" => "hero-link",
    "invoice.downloaded" => "hero-arrow-down-tray",
    "invoice.note_updated" => "hero-pencil",
    "invoice.billing_date_changed" => "hero-calendar",
    "invoice.updated" => "hero-pencil-square"
  }

  @action_prefix_icons [
    {"invoice.comment_", "hero-chat-bubble-left"},
    {"invoice.duplicate_", "hero-document-duplicate"},
    {"invoice.extraction_", "hero-document-magnifying-glass"},
    {"payment_request.", "hero-banknotes"}
  ]

  @static_descriptions %{
    "invoice.comment_added" => "added a comment",
    "invoice.comment_edited" => "edited a comment",
    "invoice.comment_deleted" => "deleted a comment",
    "invoice.excluded" => "excluded invoice",
    "invoice.included" => "included invoice",
    "invoice.public_link_generated" => "generated public link",
    "invoice.duplicate_detected" => "duplicate detected",
    "invoice.duplicate_confirmed" => "confirmed as duplicate",
    "invoice.duplicate_dismissed" => "dismissed duplicate",
    "invoice.note_updated" => "updated note",
    "invoice.billing_date_changed" => "changed billing date",
    "invoice.extraction_completed" => "extraction completed",
    "invoice.re_extraction_triggered" => "triggered re-extraction",
    "invoice.extraction_dismissed" => "dismissed extraction warning",
    "payment_request.created" => "created payment request",
    "payment_request.paid" => "marked payment as paid",
    "payment_request.voided" => "voided payment request"
  }

  @field_labels %{
    "seller_name" => "seller name",
    "seller_nip" => "seller NIP",
    "buyer_name" => "buyer name",
    "buyer_nip" => "buyer NIP",
    "invoice_number" => "invoice number",
    "issue_date" => "issue date",
    "sales_date" => "sales date",
    "due_date" => "due date",
    "net_amount" => "net amount",
    "gross_amount" => "gross amount",
    "extraction_status" => "extraction status",
    "billing_date_from" => "billing from",
    "billing_date_to" => "billing to",
    "seller_address" => "seller address",
    "buyer_address" => "buyer address",
    "purchase_order" => "PO number"
  }

  attr :activity_log, :list, required: true
  attr :activity_log_empty, :boolean, required: true

  @doc "Renders the full timeline, including the empty-state message when there are no entries."
  @spec timeline(map()) :: Phoenix.LiveView.Rendered.t()
  def timeline(assigns) do
    ~H"""
    <div :if={@activity_log_empty} class="text-sm text-muted-foreground italic">
      No activity recorded yet
    </div>

    <div :if={!@activity_log_empty} class="relative">
      <span
        aria-hidden="true"
        class="absolute left-4 top-4 bottom-4 w-px -translate-x-px bg-border"
      />
      <ul
        id="activity-log-stream"
        phx-update="stream"
        class="relative space-y-5"
      >
        <li :for={{dom_id, entry} <- @activity_log} id={dom_id} class="flex items-start gap-3">
          <.activity_icon action={entry.action} metadata={entry.metadata} />
          <div class="min-w-0 flex-1 pt-1">
            <div class="text-sm">
              <span class="font-medium">{entry.actor_label || "System"}</span>
              <span class="text-muted-foreground"> · {describe_action(entry)}</span>
            </div>
            <div class="mt-0.5 font-mono text-xs text-muted-foreground">
              <.local_datetime at={entry.inserted_at} id={"activity-ts-#{entry.id}"} />
            </div>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :action, :string, required: true
  attr :metadata, :map, default: %{}

  @doc "Renders the circular colored icon for a single activity entry."
  @spec activity_icon(map()) :: Phoenix.LiveView.Rendered.t()
  def activity_icon(assigns) do
    assigns =
      assigns
      |> assign(:icon_name, icon_for_action(assigns.action))
      |> assign(:palette, icon_palette(assigns.action, assigns.metadata))

    ~H"""
    <span class={[
      "relative z-10 inline-flex size-8 shrink-0 items-center justify-center rounded-full",
      @palette
    ]}>
      <.icon name={@icon_name} class="size-4" />
    </span>
    """
  end

  @doc "Returns Tailwind classes for the icon background based on action category."
  @spec icon_palette(String.t(), map()) :: String.t()
  def icon_palette("invoice.status_changed", %{"new_status" => "approved"}),
    do: "bg-emerald-600 text-white"

  def icon_palette("invoice.status_changed", %{"new_status" => "rejected"}),
    do: "bg-red-600 text-white"

  def icon_palette(action, _metadata) do
    cond do
      String.starts_with?(action, "invoice.classification") -> "bg-blue-600 text-white"
      String.starts_with?(action, "invoice.extraction") -> "bg-blue-600 text-white"
      action == "invoice.re_extraction_triggered" -> "bg-blue-600 text-white"
      String.starts_with?(action, "invoice.duplicate") -> "bg-amber-500 text-white"
      String.starts_with?(action, "payment_request") -> "bg-emerald-600 text-white"
      true -> "bg-muted text-muted-foreground"
    end
  end

  @doc "Returns a human-readable description for an audit log entry."
  @spec describe_action(map()) :: String.t()
  def describe_action(%{action: action, metadata: metadata}) do
    case Map.fetch(@static_descriptions, action) do
      {:ok, desc} -> desc
      :error -> describe_dynamic_action(action, metadata)
    end
  end

  @spec icon_for_action(String.t()) :: String.t()
  defp icon_for_action(action) do
    Map.get(@action_icons, action) || icon_for_action_prefix(action)
  end

  @spec icon_for_action_prefix(String.t()) :: String.t()
  defp icon_for_action_prefix(action) do
    @action_prefix_icons
    |> Enum.find_value(fn {prefix, icon} ->
      if String.starts_with?(action, prefix), do: icon
    end)
    |> Kernel.||("hero-information-circle")
  end

  @spec describe_dynamic_action(String.t(), map()) :: String.t()
  defp describe_dynamic_action("invoice.created", metadata) do
    case metadata["source"] do
      nil -> "added invoice"
      source -> "added invoice via #{source}"
    end
  end

  defp describe_dynamic_action("invoice.status_changed", metadata) do
    "changed status to #{metadata["new_status"] || "unknown"}"
  end

  defp describe_dynamic_action("invoice.classification_changed", metadata) do
    field = metadata["field"] || "classification"
    old_name = metadata["old_name"]
    new_name = metadata["new_name"]

    cond do
      old_name && new_name -> "updated #{field} from #{old_name} to #{new_name}"
      new_name -> "set #{field} to #{new_name}"
      old_name -> "removed #{field} #{old_name}"
      true -> "updated #{field}"
    end
  end

  defp describe_dynamic_action("invoice.access_changed", metadata) do
    "changed access to #{metadata["change_type"] || "access"}"
  end

  defp describe_dynamic_action("invoice.downloaded", metadata) do
    "downloaded #{metadata["format"] || "file"}"
  end

  defp describe_dynamic_action("invoice.updated", metadata) do
    case metadata["changed_fields"] do
      fields when is_list(fields) and fields != [] ->
        humanized = Enum.map_join(fields, ", ", &humanize_field/1)
        "updated #{humanized}"

      _ ->
        "updated invoice fields"
    end
  end

  defp describe_dynamic_action(action, _metadata) do
    action |> String.replace(".", " ") |> String.replace("_", " ")
  end

  @doc "Returns a human-readable label for an invoice field name (e.g. \"seller_nip\" → \"seller NIP\")."
  @spec humanize_field(String.t()) :: String.t()
  def humanize_field(field), do: Map.get(@field_labels, field, String.replace(field, "_", " "))
end
