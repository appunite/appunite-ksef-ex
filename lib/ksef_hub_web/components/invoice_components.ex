defmodule KsefHubWeb.InvoiceComponents do
  @moduledoc """
  Shared UI components for invoice display across LiveViews.
  """

  use Phoenix.Component

  import KsefHubWeb.CoreComponents, only: [badge: 1]

  require Logger

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
  def display_status(%{status: status}), do: status
  def display_status(%{"status" => status}), do: status

  @doc "Renders a category badge with emoji and name, or \"-\" when nil."
  @spec category_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :category, :map, default: nil

  def category_badge(assigns) do
    ~H"""
    <span :if={@category} class="inline-flex items-center gap-1 text-xs">
      <span :if={@category.emoji}>{@category.emoji}</span>
      <span>{@category.name || @category.identifier}</span>
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

  @doc "Formats a date as YYYY-MM-DD, or returns \"-\" for nil."
  @spec format_date(Date.t() | nil) :: String.t()
  def format_date(nil), do: "-"
  def format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

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

  @doc "Formats a numeric amount, or returns \"-\" for nil/unknown types."
  @spec format_amount(Decimal.t() | number() | nil) :: String.t()
  def format_amount(nil), do: "-"
  def format_amount(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  def format_amount(n) when is_integer(n), do: n |> Decimal.new() |> Decimal.to_string(:normal)

  def format_amount(f) when is_float(f),
    do: f |> Decimal.from_float() |> Decimal.to_string(:normal)

  def format_amount(_), do: "-"

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
      title="Access restricted to invited reviewers"
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
        <tr class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground">Buyer</td>
          <td class="py-1.5 text-right">
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
        <tr class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground">Seller</td>
          <td class="py-1.5 text-right">
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
        <tr class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Number</td>
          <td class="py-1.5 text-right">{@invoice.invoice_number}</td>
        </tr>
        <tr class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground">Date</td>
          <td class="py-1.5 text-right">{format_date(@invoice.issue_date)}</td>
        </tr>
        <tr :if={@invoice.sales_date} class="border-b border-border/50" data-testid="sales-date">
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Sales Date</td>
          <td class="py-1.5 text-right">{format_date(@invoice.sales_date)}</td>
        </tr>
        <tr :if={@invoice.due_date} class="border-b border-border/50" data-testid="due-date">
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Due Date</td>
          <td class="py-1.5 text-right">{format_date(@invoice.due_date)}</td>
        </tr>
        <tr class={[
          "border-b border-border/50",
          is_nil(@invoice.net_amount) && "bg-warning/5"
        ]}>
          <td class="py-1.5 pr-3 text-muted-foreground">Netto</td>
          <td class="py-1.5 text-right font-mono">
            {format_amount(@invoice.net_amount)} {@invoice.currency}
          </td>
        </tr>
        <tr class={[
          "border-b border-border/50",
          is_nil(@invoice.gross_amount) && "bg-warning/5"
        ]}>
          <td class="py-1.5 pr-3 text-muted-foreground">Brutto</td>
          <td class="py-1.5 text-right font-mono font-bold">
            {format_amount(@invoice.gross_amount)} {@invoice.currency}
          </td>
        </tr>
        <tr :if={@invoice.ksef_number} class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground">KSeF</td>
          <td class="py-1.5 text-right font-mono break-all">
            {@invoice.ksef_number}
          </td>
        </tr>
        <tr :if={@invoice.purchase_order} class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">PO</td>
          <td class="py-1.5 text-right font-mono break-all">
            {@invoice.purchase_order}
          </td>
        </tr>
        <tr :if={@invoice.iban} class="border-b border-border/50" data-testid="iban">
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">IBAN</td>
          <td class="py-1.5 text-right font-mono break-all">
            {@invoice.iban}
          </td>
        </tr>
        <tr :if={@invoice.ksef_acquisition_date}>
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Acquired</td>
          <td class="py-1.5 text-right">
            {format_datetime(@invoice.ksef_acquisition_date)}
          </td>
        </tr>
        <tr class="border-b border-border/50">
          <td class="py-1.5 pr-3 text-muted-foreground whitespace-nowrap">Created</td>
          <td class="py-1.5 text-right">
            {format_datetime(@invoice.inserted_at)}
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
