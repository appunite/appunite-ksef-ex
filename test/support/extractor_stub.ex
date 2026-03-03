defmodule KsefHub.InvoiceExtractor.StubClient do
  @moduledoc false
  @behaviour KsefHub.InvoiceExtractor.Behaviour

  @impl true
  def extract(_pdf_binary, _opts) do
    {:ok,
     %{
       "seller_nip" => "1234567890",
       "seller_name" => "Extracted Seller Sp. z o.o.",
       "buyer_nip" => "0987654321",
       "buyer_name" => "Extracted Buyer S.A.",
       "invoice_number" => "FV/2026/EXTRACTED/001",
       "issue_date" => "2026-02-20",
       "net_amount" => "1000.00",
       "gross_amount" => "1230.00",
       "currency" => "PLN"
     }}
  end

  @impl true
  def health do
    {:ok, %{"status" => "ok"}}
  end
end
