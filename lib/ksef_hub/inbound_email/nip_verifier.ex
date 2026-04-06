defmodule KsefHub.InboundEmail.NipVerifier do
  @moduledoc """
  Delegates to `KsefHub.Invoices.NipVerifier` for backwards compatibility.

  Existing email worker code references this module. New code should use
  `KsefHub.Invoices.NipVerifier` directly.
  """

  defdelegate verify_expense(extracted, company_nip), to: KsefHub.Invoices.NipVerifier
end
