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
end
