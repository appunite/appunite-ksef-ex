defmodule KsefHubWeb.CertificateComponents do
  @moduledoc """
  Shared UI components for certificate expiry alerts.

  Used on the invoice list and certificate settings pages to warn users
  about expiring or expired KSeF certificates.
  """
  use Phoenix.Component

  import KsefHubWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a certificate expiry alert banner.

  Shows an error banner when the certificate has expired, a warning banner
  when it expires within 7 days, and nothing otherwise.

  ## Attributes

    * `:status` — certificate expiry status from `Credentials.certificate_expiry_status/1`
    * `:link_target` — optional navigation path for the action link (defaults to nil, which hides the link)

  ## Examples

      <.cert_expiry_alert status={:ok} />
      <.cert_expiry_alert status={{:expired, 3}} link_target={~p"/c/\#{id}/settings/certificates"} />
      <.cert_expiry_alert status={{:expiring_soon, 5}} link_target={~p"/c/\#{id}/settings/certificates"} />
  """
  attr :status, :any, required: true
  attr :link_target, :string, default: nil
  attr :class, :string, default: ""

  @spec cert_expiry_alert(map()) :: Rendered.t()
  def cert_expiry_alert(%{status: {:expired, _days}} = assigns) do
    ~H"""
    <div
      data-testid="certificate-expired-banner"
      class={[
        "rounded-lg border border-shad-destructive/50 bg-shad-destructive/10 p-4 flex items-start gap-3",
        @class
      ]}
    >
      <.icon name="hero-x-circle" class="size-5 text-shad-destructive mt-0.5" />
      <div>
        <p class="text-sm font-medium">Certificate expired</p>
        <p class="text-sm text-muted-foreground">
          Your KSeF certificate has expired. KSeF sync is no longer working.
          <%= if @link_target do %>
            Please <.link navigate={@link_target} class="underline">upload a new certificate</.link>
            to resume invoice synchronization.
          <% else %>
            Please generate and upload a new certificate to resume invoice synchronization.
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  def cert_expiry_alert(%{status: {:expiring_soon, days}} = assigns) do
    assigns = assign(assigns, :days, days)

    ~H"""
    <div
      data-testid="certificate-expiring-banner"
      class={[
        "rounded-lg border border-warning/50 bg-warning/10 p-4 flex items-start gap-3",
        @class
      ]}
    >
      <.icon name="hero-exclamation-triangle" class="size-5 text-warning mt-0.5" />
      <div>
        <p class="text-sm font-medium">Certificate expiring soon</p>
        <p class="text-sm text-muted-foreground">
          Your KSeF certificate expires in {@days} {if @days == 1, do: "day", else: "days"}.
          <%= if @link_target do %>
            Please
            <.link navigate={@link_target} class="underline">
              generate and upload a new certificate
            </.link>
            before it expires to avoid sync interruption.
          <% else %>
            Please generate and upload a new certificate before it expires to avoid sync interruption.
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  def cert_expiry_alert(assigns), do: ~H""
end
