defmodule KsefHub.Pdf.FallbackTemplate do
  @moduledoc """
  Renders a basic HTML invoice preview from FA(3) XML when xsltproc is unavailable.
  Uses the existing Parser to extract structured data.
  """

  alias KsefHub.Invoices.Parser

  @doc """
  Renders FA(3) XML as a simple HTML document.
  Returns `{:ok, html}` or `{:error, reason}`.
  """
  @spec render(String.t()) :: {:ok, String.t()} | {:error, term()}
  def render(xml_content) do
    case Parser.parse(xml_content) do
      {:ok, invoice} ->
        {:ok, build_html(invoice)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_html(invoice) do
    line_items_html =
      invoice.line_items
      |> Enum.map(&line_item_row/1)
      |> Enum.join("\n")

    """
    <!DOCTYPE html>
    <html lang="pl">
    <head>
      <meta charset="UTF-8">
      <title>Faktura #{escape(invoice.invoice_number)}</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 2rem; color: #333; }
        h1 { font-size: 1.5rem; border-bottom: 2px solid #333; padding-bottom: 0.5rem; }
        .parties { display: flex; gap: 2rem; margin: 1.5rem 0; }
        .party { flex: 1; padding: 1rem; background: #f5f5f5; border-radius: 4px; }
        .party h3 { margin: 0 0 0.5rem; font-size: 0.9rem; color: #666; text-transform: uppercase; }
        .party p { margin: 0.25rem 0; }
        table { width: 100%; border-collapse: collapse; margin: 1.5rem 0; }
        th, td { padding: 0.5rem; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f0f0f0; font-weight: 600; }
        td.num { text-align: right; }
        .totals { margin-top: 1rem; text-align: right; }
        .totals p { margin: 0.25rem 0; }
        .totals .gross { font-size: 1.2rem; font-weight: bold; }
      </style>
    </head>
    <body>
      <h1>Faktura VAT #{escape(invoice.invoice_number)}</h1>
      <p>Data wystawienia: #{format_date(invoice.issue_date)}</p>

      <div class="parties">
        <div class="party">
          <h3>Sprzedawca</h3>
          <p><strong>#{escape(invoice.seller_name)}</strong></p>
          <p>NIP: #{escape(invoice.seller_nip)}</p>
        </div>
        <div class="party">
          <h3>Nabywca</h3>
          <p><strong>#{escape(invoice.buyer_name)}</strong></p>
          <p>NIP: #{escape(invoice.buyer_nip)}</p>
        </div>
      </div>

      <table>
        <thead>
          <tr>
            <th>Lp.</th>
            <th>Nazwa</th>
            <th>Jm.</th>
            <th class="num">Ilosc</th>
            <th class="num">Cena jed.</th>
            <th class="num">Netto</th>
            <th class="num">VAT %</th>
          </tr>
        </thead>
        <tbody>
          #{line_items_html}
        </tbody>
      </table>

      <div class="totals">
        <p>Netto: #{format_amount(invoice.net_amount)} #{escape(invoice.currency)}</p>
        <p>VAT: #{format_amount(invoice.vat_amount)} #{escape(invoice.currency)}</p>
        <p class="gross">Brutto: #{format_amount(invoice.gross_amount)} #{escape(invoice.currency)}</p>
      </div>
    </body>
    </html>
    """
  end

  defp line_item_row(item) do
    """
        <tr>
          <td>#{escape(item.line_number)}</td>
          <td>#{escape(item.description || "")}</td>
          <td>#{escape(item.unit || "")}</td>
          <td class="num">#{format_amount(item.quantity)}</td>
          <td class="num">#{format_amount(item.unit_price)}</td>
          <td class="num">#{format_amount(item.net_amount)}</td>
          <td class="num">#{format_amount(item.vat_rate)}</td>
        </tr>
    """
  end

  defp escape(nil), do: ""

  defp escape(val) when is_binary(val),
    do: Phoenix.HTML.html_escape(val) |> Phoenix.HTML.safe_to_string()

  defp escape(val), do: escape(to_string(val))

  defp format_date(nil), do: "-"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(str) when is_binary(str), do: escape(str)

  defp format_amount(nil), do: "-"
  defp format_amount(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp format_amount(val), do: to_string(val)
end
