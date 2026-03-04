defmodule KsefHubWeb.InvoiceComponents do
  @moduledoc """
  Shared UI components for invoice display across LiveViews.
  """

  use Phoenix.Component

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

  @doc "Renders a coloured badge for the invoice status (:pending / :approved / :rejected)."
  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border",
      @status == :pending && "bg-warning/10 text-warning border-warning/20",
      @status == :approved && "bg-success/10 text-success border-success/20",
      @status == :rejected && "bg-error/10 text-error border-error/20",
      @status not in [:pending, :approved, :rejected] &&
        "bg-base-200 text-base-content/60 border-base-300"
    ]}>
      {@status}
    </span>
    """
  end

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
      Incomplete
    </span>
    """
  end

  def extraction_badge(%{status: :failed} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-error/10 text-error border-error/20">
      Failed
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

  @doc "Formats an address map as a comma-separated string, or returns \"\" for nil."
  @spec format_address(map() | nil) :: String.t()
  def format_address(nil), do: ""

  def format_address(addr) when is_map(addr) do
    addr
    |> Map.take(~w(street city postal_code country)a ++ ~w(street city postal_code country))
    |> Map.values()
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq()
    |> Enum.join(", ")
  end
end
