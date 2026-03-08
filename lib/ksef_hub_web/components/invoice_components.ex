defmodule KsefHubWeb.InvoiceComponents do
  @moduledoc """
  Shared UI components for invoice display across LiveViews.
  """

  use Phoenix.Component

  alias KsefHub.Invoices.Invoice

  @doc "Renders a coloured badge for the invoice type (:income / :expense)."
  @spec type_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :type, :atom, required: true

  def type_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border",
      @type == :income && "bg-success/10 text-success border-success/20",
      @type == :expense && "bg-warning/10 text-warning border-warning/20",
      @type not in [:income, :expense] && "bg-base-200 text-base-content/60 border-base-300"
    ]}>
      {@type}
    </span>
    """
  end

  @doc "Renders a coloured badge for the invoice status (:pending / :approved / :rejected / :duplicate). Renders nothing for nil."
  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :status, :atom, required: true

  def status_badge(%{status: nil} = assigns) do
    ~H""
  end

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border",
      @status == :pending && "bg-warning/10 text-warning border-warning/20",
      @status == :approved && "bg-success/10 text-success border-success/20",
      @status in [:rejected, :duplicate] && "bg-error/10 text-error border-error/20",
      @status not in [:pending, :approved, :rejected, :duplicate] &&
        "bg-base-200 text-base-content/60 border-base-300"
    ]}>
      {@status}
    </span>
    """
  end

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
      <span>{@category.name}</span>
    </span>
    <span :if={!@category} class="text-base-content/40">-</span>
    """
  end

  @doc "Renders a list of tag badges, or \"-\" when empty."
  @spec tag_list(map()) :: Phoenix.LiveView.Rendered.t()
  attr :tags, :list, default: []

  def tag_list(assigns) do
    ~H"""
    <div :if={@tags != []} class="flex flex-wrap gap-1">
      <span
        :for={tag <- @tags}
        class="inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-base-200 text-base-content/70"
      >
        {tag.name}
      </span>
    </div>
    <span :if={@tags == []} class="text-base-content/40">-</span>
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
    <span
      :if={@show}
      class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-info/10 text-info border-info/20"
    >
      needs review
    </span>
    """
  end

  @doc """
  Renders a coloured badge for extraction status.

  Renders nothing for nil or :complete (clean state). Shows an orange
  "Incomplete" badge for :partial and a red "Failed" badge for :failed.
  """
  @spec extraction_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :status, :atom, required: true

  def extraction_badge(%{status: status} = assigns) when status in [nil, :complete], do: ~H""

  def extraction_badge(%{status: :partial} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-warning/10 text-warning border-warning/20">
      incomplete
    </span>
    """
  end

  def extraction_badge(%{status: :failed} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-error/10 text-error border-error/20">
      failed
    </span>
    """
  end

  @doc "Formats a date as YYYY-MM-DD, or returns \"-\" for nil."
  @spec format_date(Date.t() | nil) :: String.t()
  def format_date(nil), do: "-"
  def format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

  @doc "Formats a numeric amount, or returns \"-\" for nil/unknown types."
  @spec format_amount(Decimal.t() | number() | nil) :: String.t()
  def format_amount(nil), do: "-"
  def format_amount(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  def format_amount(n) when is_integer(n), do: n |> Decimal.new() |> Decimal.to_string(:normal)

  def format_amount(f) when is_float(f),
    do: f |> Decimal.from_float() |> Decimal.to_string(:normal)

  def format_amount(_), do: "-"

  @doc "Formats a datetime as YYYY-MM-DD HH:MM UTC, or returns \"-\" for nil."
  @spec format_datetime(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  def format_datetime(nil), do: "-"
  def format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  @doc "Returns a human-readable label for who added an invoice, combining source and creator info. Delegates to `Invoice.added_by_label/1`."
  @spec added_by_label(Invoice.t()) :: String.t()
  defdelegate added_by_label(invoice), to: Invoice

  attr :invoice, :map, required: true
  attr :show_added_by, :boolean, default: false

  @doc "Renders a read-only invoice details table (buyer, seller, amounts, dates, KSeF number)."
  @spec invoice_details_table(map()) :: Phoenix.LiveView.Rendered.t()
  def invoice_details_table(assigns) do
    ~H"""
    <table class="text-sm w-full">
      <tbody>
        <tr class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60">Buyer</td>
          <td class="py-1.5 text-right">
            <div>{@invoice.buyer_name}</div>
            <div class="text-xs text-base-content/50">{@invoice.buyer_nip}</div>
            <div
              :if={format_address(@invoice.buyer_address) != ""}
              class="text-xs text-base-content/50"
              data-testid="buyer-address"
            >
              {format_address(@invoice.buyer_address)}
            </div>
          </td>
        </tr>
        <tr class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60">Seller</td>
          <td class="py-1.5 text-right">
            <div>{@invoice.seller_name}</div>
            <div class="text-xs text-base-content/50">{@invoice.seller_nip}</div>
            <div
              :if={format_address(@invoice.seller_address) != ""}
              class="text-xs text-base-content/50"
              data-testid="seller-address"
            >
              {format_address(@invoice.seller_address)}
            </div>
          </td>
        </tr>
        <tr class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Number</td>
          <td class="py-1.5 text-right">{@invoice.invoice_number}</td>
        </tr>
        <tr class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60">Date</td>
          <td class="py-1.5 text-right">{format_date(@invoice.issue_date)}</td>
        </tr>
        <tr :if={@invoice.sales_date} class="border-b border-base-300/50" data-testid="sales-date">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Sales Date</td>
          <td class="py-1.5 text-right">{format_date(@invoice.sales_date)}</td>
        </tr>
        <tr :if={@invoice.due_date} class="border-b border-base-300/50" data-testid="due-date">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Due Date</td>
          <td class="py-1.5 text-right">{format_date(@invoice.due_date)}</td>
        </tr>
        <tr class={[
          "border-b border-base-300/50",
          is_nil(@invoice.net_amount) && "bg-warning/5"
        ]}>
          <td class="py-1.5 pr-3 text-base-content/60">Netto</td>
          <td class="py-1.5 text-right font-mono">
            {format_amount(@invoice.net_amount)} {@invoice.currency}
          </td>
        </tr>
        <tr class={[
          "border-b border-base-300/50",
          is_nil(@invoice.gross_amount) && "bg-warning/5"
        ]}>
          <td class="py-1.5 pr-3 text-base-content/60">Brutto</td>
          <td class="py-1.5 text-right font-mono font-bold">
            {format_amount(@invoice.gross_amount)} {@invoice.currency}
          </td>
        </tr>
        <tr :if={@invoice.ksef_number} class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60">KSeF</td>
          <td class="py-1.5 text-right font-mono text-xs break-all">
            {@invoice.ksef_number}
          </td>
        </tr>
        <tr :if={@invoice.purchase_order} class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">PO</td>
          <td class="py-1.5 text-right font-mono text-sm break-all">
            {@invoice.purchase_order}
          </td>
        </tr>
        <tr :if={@invoice.iban} class="border-b border-base-300/50" data-testid="iban">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">IBAN</td>
          <td class="py-1.5 text-right font-mono text-xs break-all">
            {@invoice.iban}
          </td>
        </tr>
        <tr :if={@invoice.ksef_acquisition_date}>
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Acquired</td>
          <td class="py-1.5 text-right text-xs">
            {format_datetime(@invoice.ksef_acquisition_date)}
          </td>
        </tr>
        <tr class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Created</td>
          <td class="py-1.5 text-right text-xs">
            {format_datetime(@invoice.inserted_at)}
          </td>
        </tr>
        <tr :if={@show_added_by} class="border-b border-base-300/50">
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Added by</td>
          <td class="py-1.5 text-right text-xs">{added_by_label(@invoice)}</td>
        </tr>
        <tr :if={NaiveDateTime.compare(@invoice.updated_at, @invoice.inserted_at) != :eq}>
          <td class="py-1.5 pr-3 text-base-content/60 whitespace-nowrap">Updated</td>
          <td class="py-1.5 text-right text-xs">
            {format_datetime(@invoice.updated_at)}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

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
      {:ok, html} -> html
      {:error, _} -> nil
    end
  end

  def generate_preview(_invoice), do: nil
end
