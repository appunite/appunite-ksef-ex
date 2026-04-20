defmodule KsefHubWeb.InvoiceComponents do
  @moduledoc """
  Shared UI components for invoice display across LiveViews.
  """

  use Phoenix.Component

  import KsefHubWeb.CoreComponents, only: [badge: 1, button: 1, icon: 1]

  use Phoenix.VerifiedRoutes, endpoint: KsefHubWeb.Endpoint, router: KsefHubWeb.Router

  alias KsefHub.Invoices.Invoice

  require Logger

  @doc """
  Renders the duplicate-status banner for an invoice.

  Shows nothing when the invoice is not a duplicate. Otherwise renders a
  warning (suspected), error (confirmed), or muted (dismissed) banner with
  a link to the original invoice.
  """
  @spec duplicate_banner(map()) :: Phoenix.LiveView.Rendered.t()
  attr :invoice, :map, required: true
  attr :company_id, :string, required: true
  attr :can_mutate, :boolean, default: false

  def duplicate_banner(%{invoice: %{duplicate_of_id: nil}} = assigns), do: ~H""

  def duplicate_banner(%{invoice: %{duplicate_status: :suspected}} = assigns) do
    ~H"""
    <div
      class="flex items-center gap-3 rounded-md border border-warning/20 bg-warning/5 p-4 mt-4"
      role="alert"
      data-testid="duplicate-warning"
    >
      <.icon name="hero-document-duplicate" class="size-5" />
      <span>
        This invoice may be a duplicate.
        <.duplicate_link company_id={@company_id} invoice_id={@invoice.duplicate_of_id}>
          View original
        </.duplicate_link>
      </span>
      <div :if={@can_mutate} class="flex-none flex gap-2">
        <.button variant="ghost" phx-click="dismiss_duplicate">
          Not a duplicate
        </.button>
        <.button variant="warning" phx-click="confirm_duplicate">
          Confirm duplicate
        </.button>
      </div>
    </div>
    """
  end

  def duplicate_banner(%{invoice: %{duplicate_status: :confirmed}} = assigns) do
    ~H"""
    <div
      class="flex items-center gap-3 rounded-md border border-error/20 bg-error/5 p-4 mt-4"
      role="alert"
      data-testid="duplicate-confirmed"
    >
      <.icon name="hero-document-duplicate" class="size-5" />
      <span>
        This invoice is a confirmed duplicate of <.duplicate_link
          company_id={@company_id}
          invoice_id={@invoice.duplicate_of_id}
        >
          the original
        </.duplicate_link>.
      </span>
    </div>
    """
  end

  def duplicate_banner(%{invoice: %{duplicate_status: :dismissed}} = assigns) do
    ~H"""
    <div
      class="flex items-center gap-3 rounded-md border border-muted bg-muted/30 p-3 mt-4 text-sm text-muted-foreground"
      data-testid="duplicate-dismissed"
    >
      <.icon name="hero-document-duplicate" class="size-4" />
      <span>
        Previously flagged as a possible duplicate of
        <.duplicate_link
          company_id={@company_id}
          invoice_id={@invoice.duplicate_of_id}
        >
          another invoice
        </.duplicate_link>
        — dismissed.
      </span>
    </div>
    """
  end

  @spec duplicate_link(map()) :: Phoenix.LiveView.Rendered.t()
  attr :company_id, :string, required: true
  attr :invoice_id, :string, required: true
  slot :inner_block, required: true

  defp duplicate_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/c/#{@company_id}/invoices/#{@invoice_id}"}
      class="text-shad-primary font-medium underline underline-offset-4 hover:opacity-80"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a badge for the invoice kind. Shows a muted badge for plain VAT invoices,
  a purple badge for correction kinds, and an info badge for other non-standard kinds
  (advance, simplified, etc.). Labels are rendered as returned by
  `KsefHub.Invoices.Invoice.invoice_kind_label/1` (mostly lowercase; `:vat` renders as `"VAT"`).
  """
  @spec invoice_kind_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :kind, :atom, required: true

  def invoice_kind_badge(%{kind: nil} = assigns), do: ~H""

  def invoice_kind_badge(assigns) do
    assigns =
      assigns
      |> assign(:label, Invoice.invoice_kind_label(assigns.kind))
      |> assign(
        :variant,
        cond do
          assigns.kind == :vat -> "muted"
          assigns.kind in Invoice.correction_kinds() -> "purple"
          true -> "info"
        end
      )

    ~H"""
    <.badge variant={@variant}>{@label}</.badge>
    """
  end

  @doc """
  Renders a correction details panel for correction invoices. Shows the corrected
  invoice reference, correction reason, type, and period. Renders nothing for
  non-correction invoices.
  """
  @spec correction_details(map()) :: Phoenix.LiveView.Rendered.t()
  attr :invoice, :map, required: true
  attr :company_id, :string, required: true

  def correction_details(%{invoice: %{invoice_kind: kind}} = assigns)
      when kind in [:correction, :advance_correction, :settlement_correction] do
    assigns =
      assign(
        assigns,
        :type_label,
        Invoice.correction_type_label(assigns.invoice.correction_type)
      )

    ~H"""
    <div
      class="rounded-md border border-purple/20 bg-purple/5 p-4 mt-4"
      data-testid="correction-details"
    >
      <h3 class="flex items-center gap-2 text-base font-semibold mb-2">
        <.icon name="hero-arrow-uturn-left" class="size-4" /> Correction invoice
      </h3>
      <table class="text-sm w-full">
        <tbody>
          <tr :if={@invoice.corrected_invoice_number} class="border-b border-border/50 last:border-0">
            <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Corrected invoice</td>
            <td class="py-1.5 text-right">
              <%= if @invoice.corrects_invoice_id do %>
                <.link
                  navigate={~p"/c/#{@company_id}/invoices/#{@invoice.corrects_invoice_id}"}
                  class="text-shad-primary underline-offset-4 hover:underline"
                >
                  {@invoice.corrected_invoice_number}
                </.link>
              <% else %>
                {@invoice.corrected_invoice_number}
              <% end %>
            </td>
          </tr>
          <tr
            :if={@invoice.corrected_invoice_ksef_number}
            class="border-b border-border/50 last:border-0"
          >
            <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Original KSeF</td>
            <td class="py-1.5 text-right font-mono break-all">
              {@invoice.corrected_invoice_ksef_number}
            </td>
          </tr>
          <tr :if={@invoice.corrected_invoice_date} class="border-b border-border/50 last:border-0">
            <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Original date</td>
            <td class="py-1.5 text-right">{format_date(@invoice.corrected_invoice_date)}</td>
          </tr>
          <tr :if={@invoice.correction_reason} class="border-b border-border/50 last:border-0">
            <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Reason</td>
            <td class="py-1.5 text-right">{@invoice.correction_reason}</td>
          </tr>
          <tr :if={@type_label != ""} class="border-b border-border/50 last:border-0">
            <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Effect</td>
            <td class="py-1.5 text-right">{@type_label}</td>
          </tr>
          <tr
            :if={@invoice.correction_period_from || @invoice.correction_period_to}
            class="border-b border-border/50 last:border-0"
          >
            <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Period</td>
            <td class="py-1.5 text-right">
              {format_date(@invoice.correction_period_from)} – {format_date(
                @invoice.correction_period_to
              )}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def correction_details(assigns), do: ~H""

  @doc """
  Renders a table of related invoices: corrections for an original, or the
  original for a correction. Renders nothing when there are no related invoices.
  """
  @spec related_invoices(map()) :: Phoenix.LiveView.Rendered.t()
  attr :invoice, :map, required: true
  attr :company_id, :string, required: true

  def related_invoices(assigns) do
    corrections = loaded_list(assigns.invoice, :corrections)
    corrects = loaded_assoc(assigns.invoice, :corrects_invoice)

    original = if corrects, do: [{corrects, :original}], else: []
    related = original ++ Enum.map(corrections, &{&1, :correction})

    if related == [] do
      ~H""
    else
      assigns = assign(assigns, :related, related)

      ~H"""
      <div
        class="rounded-md border border-border bg-card p-4 mt-4"
        data-testid="related-invoices"
      >
        <h3 class="text-base font-semibold mb-2">Related invoices</h3>
        <table class="text-sm w-full">
          <thead>
            <tr class="border-b border-border text-muted-foreground text-left">
              <th class="py-1 pr-3 font-normal">Relation</th>
              <th class="py-1 pr-3 font-normal">Number</th>
              <th class="py-1 pr-3 font-normal">Date</th>
              <th class="py-1 font-normal">Kind</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{inv, relation} <- @related} class="border-b border-border/50 last:border-0">
              <td class="py-1.5 pr-3 text-muted-foreground">
                {if relation == :original, do: "Original", else: "Correction"}
              </td>
              <td class="py-1.5 pr-3">
                <.link
                  navigate={~p"/c/#{@company_id}/invoices/#{inv.id}"}
                  class="text-shad-primary underline-offset-4 hover:underline"
                >
                  {inv.invoice_number}
                </.link>
              </td>
              <td class="py-1.5 pr-3">{format_date(inv.issue_date)}</td>
              <td class="py-1.5"><.invoice_kind_badge kind={inv.invoice_kind} /></td>
            </tr>
          </tbody>
        </table>
      </div>
      """
    end
  end

  @spec loaded_list(map(), atom()) :: [map()]
  defp loaded_list(struct, field) do
    case Map.get(struct, field) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      list when is_list(list) -> list
    end
  end

  @spec loaded_assoc(map(), atom()) :: map() | nil
  defp loaded_assoc(struct, field) do
    case Map.get(struct, field) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      assoc -> assoc
    end
  end

  @doc "Renders a small coloured dot indicating the invoice source (ksef / email / pdf_upload / manual)."
  attr :source, :atom, values: [:ksef, :manual, :pdf_upload, :email], required: true
  attr :class, :string, default: nil

  @spec source_dot(map()) :: Phoenix.LiveView.Rendered.t()
  def source_dot(assigns) do
    assigns = assign(assigns, :color, source_dot_color(assigns.source))
    assigns = assign(assigns, :label, source_dot_label(assigns.source))

    ~H"""
    <span
      class={["inline-block w-2 h-2 rounded-full shrink-0", @color, @class]}
      title={@label}
    />
    """
  end

  @spec source_dot_color(atom()) :: String.t()
  defp source_dot_color(:ksef), do: "bg-shad-primary"
  defp source_dot_color(:email), do: "bg-info"
  defp source_dot_color(:pdf_upload), do: "bg-warning"
  defp source_dot_color(:manual), do: "bg-muted-foreground"
  defp source_dot_color(_), do: "bg-muted-foreground"

  @spec source_dot_label(atom()) :: String.t()
  defp source_dot_label(:ksef), do: "KSeF"
  defp source_dot_label(:email), do: "Email"
  defp source_dot_label(:pdf_upload), do: "PDF upload"
  defp source_dot_label(:manual), do: "Manual"
  defp source_dot_label(_), do: "Unknown"

  @doc "Renders a coloured badge for the invoice type (:income / :expense)."
  @spec type_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :type, :atom, required: true

  def type_badge(assigns) do
    assigns = assign(assigns, :variant, type_variant(assigns.type))

    ~H"""
    <.badge variant={@variant}>{@type}</.badge>
    """
  end

  @spec type_variant(atom()) :: String.t()
  defp type_variant(:income), do: "success"
  defp type_variant(:expense), do: "warning"
  defp type_variant(_), do: "muted"

  @doc "Renders a coloured badge for the invoice status (:pending / :approved / :rejected / :duplicate). Renders nothing for nil."
  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :status, :atom, required: true
  attr :label, :string, default: nil

  def status_badge(%{status: nil} = assigns) do
    ~H""
  end

  def status_badge(assigns) do
    assigns =
      assigns
      |> assign(:variant, status_variant(assigns.status))
      |> assign_new(:display_label, fn -> assigns[:label] || Atom.to_string(assigns.status) end)

    ~H"""
    <.badge variant={@variant}>{@display_label}</.badge>
    """
  end

  @spec status_variant(atom()) :: String.t()
  defp status_variant(:pending), do: "warning"
  defp status_variant(:approved), do: "success"
  defp status_variant(:rejected), do: "error"
  defp status_variant(:duplicate), do: "error"
  defp status_variant(_), do: "muted"

  @doc """
  Returns the display status for an invoice, accounting for confirmed duplicates
  and income invoices (which have no approval workflow).

  - Confirmed duplicates show as `:duplicate` regardless of actual DB status.
  - Income invoices always return `nil` (no actionable status to display).
  """
  @spec display_status(map()) :: atom() | nil
  def display_status(%{duplicate_status: :confirmed}), do: :duplicate
  def display_status(%{"duplicate_status" => :confirmed}), do: :duplicate
  def display_status(%{type: :income}), do: nil
  def display_status(%{"type" => :income}), do: nil
  def display_status(%{expense_approval_status: status}), do: status
  def display_status(%{"expense_approval_status" => status}), do: status

  @doc "Renders a category badge with emoji and name, or \"-\" when nil."
  @spec category_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :category, :map, default: nil
  attr :confidence, :float, default: nil
  attr :prediction_status, :atom, default: nil

  def category_badge(assigns) do
    ~H"""
    <span
      :if={@category}
      class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md border border-border bg-muted/50 text-xs text-foreground whitespace-nowrap max-w-[200px]"
      title={@category.name || @category.identifier}
    >
      <span :if={@category.emoji} class="shrink-0">{@category.emoji}</span>
      <span class="truncate">{@category.name || @category.identifier}</span>
      <span
        :if={@prediction_status in [:predicted, :needs_review] && @confidence}
        class="text-muted-foreground shrink-0"
      >
        · {round(@confidence * 100)}%
      </span>
    </span>
    <span :if={!@category} class="text-muted-foreground">-</span>
    """
  end

  @doc "Renders a list of tag badges, or \"-\" when empty."
  @spec tag_list(map()) :: Phoenix.LiveView.Rendered.t()
  attr :tags, :list, default: []

  def tag_list(assigns) do
    ~H"""
    <div :if={@tags != []} class="flex flex-wrap gap-1">
      <.badge :for={tag <- @tags} variant="info">{tag.name}</.badge>
    </div>
    <span :if={@tags == []} class="text-muted-foreground">-</span>
    """
  end

  @doc """
  Renders a 'needs review' badge when the invoice has unresolved issues.

  Shows when the invoice is still pending AND any of:
  - extraction is incomplete (`:partial` or `:failed`)
  - ML prediction confidence is low (`:needs_review`)
  - suspected duplicate (`:suspected`)
  """
  @spec needs_review_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :prediction_status, :atom, default: nil
  attr :duplicate_status, :atom, default: nil
  attr :extraction_status, :atom, default: nil
  attr :status, :atom, default: nil

  def needs_review_badge(assigns) do
    show? =
      assigns.status == :pending &&
        assigns.duplicate_status != :confirmed &&
        (assigns.extraction_status in [:partial, :failed] ||
           assigns.prediction_status == :needs_review ||
           assigns.duplicate_status == :suspected)

    assigns = assign(assigns, :show, show?)

    ~H"""
    <.badge :if={@show} variant="info">needs review</.badge>
    """
  end

  @doc """
  Renders a coloured badge for extraction status.

  Renders nothing for nil or :complete (clean state). Shows an orange
  "Incomplete" badge for :partial and a red "Failed" badge for :failed.
  """
  @spec extraction_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :status, :atom, required: true
  attr :duplicate_status, :atom, default: nil

  def extraction_badge(%{duplicate_status: :confirmed} = assigns), do: ~H""
  def extraction_badge(%{status: status} = assigns) when status in [nil, :complete], do: ~H""

  def extraction_badge(%{status: :partial} = assigns) do
    ~H"""
    <.badge variant="warning">incomplete</.badge>
    """
  end

  def extraction_badge(%{status: :failed} = assigns) do
    ~H"""
    <.badge variant="error">failed</.badge>
    """
  end

  @doc "Renders a payment status badge: 'paid' (success), 'pending' (warning), 'voided' (error), or nothing for nil."
  @spec payment_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :status, :atom, required: true
  attr :label, :string, default: nil

  def payment_badge(%{status: nil} = assigns), do: ~H""

  def payment_badge(assigns) do
    assigns =
      assigns
      |> assign(:variant, payment_variant(assigns.status))
      |> assign_new(:display_label, fn -> assigns[:label] || Atom.to_string(assigns.status) end)

    ~H"""
    <.badge variant={@variant}>{@display_label}</.badge>
    """
  end

  @spec payment_variant(atom()) :: String.t()
  defp payment_variant(:paid), do: "success"
  defp payment_variant(:pending), do: "warning"
  defp payment_variant(:voided), do: "error"
  defp payment_variant(_), do: "muted"

  @doc "Renders an 'excluded' badge when the invoice is excluded, nothing otherwise."
  @spec excluded_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :is_excluded, :boolean, required: true

  def excluded_badge(%{is_excluded: true} = assigns) do
    ~H"""
    <.badge variant="muted">excluded</.badge>
    """
  end

  def excluded_badge(assigns), do: ~H""

  @doc """
  Renders a two-line gross/net amount cell matching the design system (Rule 2).

  Gross (brutto) is the primary line: `font-mono text-sm tabular-nums`.
  Net (netto) is the secondary line: `font-mono text-[11px] tabular-nums text-muted-foreground`.
  Currency is appended as a muted suffix after the gross amount.

  Use inside a right-aligned table column (`class="text-right"`).

  ## Examples

      <.invoice_amount gross={inv.gross_amount} net={inv.net_amount} currency={inv.currency} />
  """
  attr :gross, :any, required: true, doc: "gross amount (Decimal, number, or nil)"

  attr :net, :any,
    default: nil,
    doc: "net amount shown as secondary line (Decimal, number, or nil)"

  attr :currency, :string, required: true

  @spec invoice_amount(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_amount(assigns) do
    ~H"""
    <div class="font-mono text-sm tabular-nums leading-tight whitespace-nowrap">
      {if @gross, do: format_amount(@gross), else: "—"}
      <span :if={@gross} class="text-xs text-muted-foreground ml-1">{@currency}</span>
    </div>
    <div
      :if={@net}
      class="font-mono text-[11px] tabular-nums leading-tight text-muted-foreground mt-0.5 whitespace-nowrap"
    >
      {format_amount(@net)} <span class="opacity-70">net</span>
    </div>
    """
  end

  @doc "Formats a date as YYYY-MM-DD, or returns \"-\" for nil."
  @spec format_date(Date.t() | nil) :: String.t()
  def format_date(nil), do: "-"
  def format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

  @doc "Formats a date as \"17 Apr\" for compact table display."
  @spec format_date_short(Date.t() | nil) :: String.t()
  def format_date_short(nil), do: "—"
  def format_date_short(date), do: Calendar.strftime(date, "%-d %b")

  @doc "Formats a date as \"Mon YYYY\" for billing period display."
  @spec format_month(Date.t() | nil) :: String.t()
  def format_month(nil), do: "-"
  def format_month(date), do: Calendar.strftime(date, "%b %Y")

  @doc ~s(Formats a billing period range. Single-month shows "Feb 2026", multi-month shows "Feb 2026 – Apr 2026".)
  @spec format_billing_period(Date.t() | nil, Date.t() | nil) :: String.t()
  def format_billing_period(nil, _), do: "Not set"
  def format_billing_period(_, nil), do: "Not set"

  def format_billing_period(from, to) do
    if Date.compare(from, to) == :eq do
      format_month(from)
    else
      ~s(#{format_month(from)} – #{format_month(to)})
    end
  end

  @doc ~s|Formats a numeric amount with space thousands separator (e.g. "1 525.20"), or returns "-" for nil.|
  @spec format_amount(Decimal.t() | number() | nil) :: String.t()
  def format_amount(nil), do: "-"

  def format_amount(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> format_with_thousands()
  end

  def format_amount(n) when is_integer(n), do: n |> Decimal.new() |> format_amount()

  def format_amount(f) when is_float(f), do: f |> Decimal.from_float() |> format_amount()

  def format_amount(_), do: "-"

  @spec format_with_thousands(String.t()) :: String.t()
  defp format_with_thousands(str) do
    case String.split(str, ".") do
      [int_part, dec_part] ->
        "#{insert_thousands(int_part)}.#{dec_part}"

      [int_part] ->
        insert_thousands(int_part)
    end
  end

  @spec insert_thousands(String.t()) :: String.t()
  defp insert_thousands(int_str) do
    {sign, digits} =
      if String.starts_with?(int_str, "-"),
        do: {"-", String.slice(int_str, 1..-1//1)},
        else: {"", int_str}

    grouped =
      digits
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join("\u00A0", &Enum.join/1)
      |> String.reverse()

    sign <> grouped
  end

  @doc "Formats a datetime as YYYY-MM-DD HH:MM, or returns \"-\" for nil. DateTime values must be in UTC (as produced by Ecto's `:utc_datetime` types)."
  @spec format_datetime(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  def format_datetime(nil), do: "-"
  def format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  def format_datetime(%DateTime{utc_offset: 0, std_offset: 0} = dt),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  @doc "Renders a datetime in the user's local timezone via a JS hook. Falls back to UTC format in the server-rendered HTML."
  @spec local_datetime(map()) :: Phoenix.LiveView.Rendered.t()
  attr :at, :any, required: true, doc: "A DateTime or NaiveDateTime value"
  attr :id, :string, required: true, doc: "Stable DOM id for LiveView diffing"

  def local_datetime(%{at: nil} = assigns) do
    ~H"-"
  end

  def local_datetime(assigns) do
    iso =
      case assigns.at do
        %DateTime{} -> DateTime.to_iso8601(assigns.at)
        %NaiveDateTime{} -> NaiveDateTime.to_iso8601(assigns.at) <> "Z"
      end

    assigns = assign(assigns, :iso, iso)

    ~H"""
    <time id={@id} datetime={@iso} phx-hook="LocalTime">
      {format_datetime(@at)}
    </time>
    """
  end

  @doc "Renders an inline lock icon for access-restricted invoices."
  @spec restricted_icon(map()) :: Phoenix.LiveView.Rendered.t()
  def restricted_icon(assigns) do
    ~H"""
    <span
      class="inline-flex items-center ml-1.5 text-muted-foreground align-middle"
      title="Access restricted to invited members"
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="size-3.5">
        <path
          fill-rule="evenodd"
          d="M8 1a3.5 3.5 0 0 0-3.5 3.5V7A1.5 1.5 0 0 0 3 8.5v4A1.5 1.5 0 0 0 4.5 14h7a1.5 1.5 0 0 0 1.5-1.5v-4A1.5 1.5 0 0 0 11.5 7V4.5A3.5 3.5 0 0 0 8 1Zm2 6V4.5a2 2 0 1 0-4 0V7h4Z"
          clip-rule="evenodd"
        />
      </svg>
    </span>
    """
  end

  attr :invoice, :map, required: true

  @doc "Renders a read-only invoice details table (buyer, seller, amounts, dates, KSeF number)."
  @spec invoice_details_table(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_details_table(assigns) do
    ~H"""
    <table class="text-sm w-full">
      <tbody>
        <tr class="border-b border-border/50 last:border-0">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground align-top">
            Buyer
          </td>
          <td class="py-1.5">
            <div>{@invoice.buyer_name}</div>
            <div class="text-xs text-muted-foreground">{@invoice.buyer_nip}</div>
            <div
              :if={format_address(@invoice.buyer_address) != ""}
              class="text-xs text-muted-foreground"
              data-testid="buyer-address"
            >
              {format_address(@invoice.buyer_address)}
            </div>
          </td>
        </tr>
        <tr class="border-b border-border/50 last:border-0">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground align-top">
            Seller
          </td>
          <td class="py-1.5">
            <div>{@invoice.seller_name}</div>
            <div class="text-xs text-muted-foreground">{@invoice.seller_nip}</div>
            <div
              :if={format_address(@invoice.seller_address) != ""}
              class="text-xs text-muted-foreground"
              data-testid="seller-address"
            >
              {format_address(@invoice.seller_address)}
            </div>
          </td>
        </tr>
        <tr class="border-b border-border/50 last:border-0">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground whitespace-nowrap">
            Number
          </td>
          <td class="py-1.5">{@invoice.invoice_number}</td>
        </tr>
        <tr class="border-b border-border/50 last:border-0">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground">Date</td>
          <td class="py-1.5">{format_date(@invoice.issue_date)}</td>
        </tr>
        <tr
          :if={@invoice.sales_date}
          class="border-b border-border/50 last:border-0"
          data-testid="sales-date"
        >
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground whitespace-nowrap">
            Sales Date
          </td>
          <td class="py-1.5">{format_date(@invoice.sales_date)}</td>
        </tr>
        <tr
          :if={@invoice.due_date}
          class="border-b border-border/50 last:border-0"
          data-testid="due-date"
        >
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground whitespace-nowrap">
            Due Date
          </td>
          <td class="py-1.5">{format_date(@invoice.due_date)}</td>
        </tr>
        <tr class={[
          "border-b border-border/50 last:border-0",
          is_nil(@invoice.net_amount) && "bg-warning/5"
        ]}>
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground">Netto</td>
          <td class="py-1.5 font-mono">
            {format_amount(@invoice.net_amount)} {@invoice.currency}
          </td>
        </tr>
        <tr class={[
          "border-b border-border/50 last:border-0",
          is_nil(@invoice.gross_amount) && "bg-warning/5"
        ]}>
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground">Brutto</td>
          <td class="py-1.5 font-mono font-bold">
            {format_amount(@invoice.gross_amount)} {@invoice.currency}
          </td>
        </tr>
        <tr :if={@invoice.ksef_number} class="border-b border-border/50 last:border-0">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground">KSeF</td>
          <td class="py-1.5 font-mono break-all">
            {@invoice.ksef_number}
          </td>
        </tr>
        <tr :if={@invoice.purchase_order} class="border-b border-border/50 last:border-0">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground whitespace-nowrap">
            PO
          </td>
          <td class="py-1.5 font-mono break-all">
            {@invoice.purchase_order}
          </td>
        </tr>
        <tr :if={@invoice.iban} class="border-b border-border/50 last:border-0" data-testid="iban">
          <td class="py-1.5 pr-3 text-xs uppercase tracking-wider text-muted-foreground whitespace-nowrap">
            IBAN
          </td>
          <td class="py-1.5 font-mono break-all">
            {@invoice.iban}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc "Renders a prediction hint showing confidence level or manual adjustment status."
  @spec prediction_hint(map()) :: Phoenix.LiveView.Rendered.t()
  attr :predicted_at, :any, required: true
  attr :status, :atom, required: true
  attr :confidence, :any, required: true
  attr :threshold, :float, required: true
  attr :label, :string, required: true
  attr :testid, :string, required: true

  def prediction_hint(assigns) do
    assigns = assign(assigns, :show_hint, show_prediction_hint?(assigns))

    ~H"""
    <p :if={@show_hint} class="text-xs mt-1 opacity-60" data-testid={@testid}>
      <%= cond do %>
        <% @status == :manual -> %>
          Manually adjusted
        <% @confidence && @confidence >= @threshold -> %>
          Predicted with {Float.round(@confidence * 100, 1)}% probability, feel free to adjust
        <% true -> %>
          Could not predict {@label} automatically ({Float.round((@confidence || 0.0) * 100, 1)}% confidence)
      <% end %>
    </p>
    """
  end

  @spec show_prediction_hint?(map()) :: boolean()
  defp show_prediction_hint?(%{predicted_at: nil}), do: false
  defp show_prediction_hint?(%{status: :manual}), do: true
  defp show_prediction_hint?(%{confidence: confidence}) when is_number(confidence), do: true
  defp show_prediction_hint?(_assigns), do: false

  @doc "Formats an address map as a comma-separated string. Delegates to Invoice.format_address/1."
  @spec format_address(map() | nil) :: String.t()
  defdelegate format_address(addr), to: KsefHub.Invoices.Invoice

  @doc "Generates an HTML preview for an invoice using the configured PDF renderer. Returns nil on failure or missing XML."
  @spec generate_preview(map()) :: String.t() | nil
  def generate_preview(%{xml_file: %{content: content}} = invoice)
      when is_binary(content) and content != "" do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)
    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_html(content, metadata) do
      {:ok, html} ->
        html

      {:error, err} ->
        Logger.warning("Preview generation failed for invoice #{invoice.id}: #{inspect(err)}")
        nil
    end
  end

  def generate_preview(_invoice), do: nil
end
