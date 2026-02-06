defmodule KsefHubWeb.InvoiceLive.Index do
  use KsefHubWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <h1 class="text-2xl font-bold mb-4">Invoices</h1>
      <p>Invoice browser — full implementation in Phase 6.</p>
    </div>
    """
  end
end
