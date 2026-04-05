defmodule KsefHub.Invoices.AutoApproval do
  @moduledoc """
  Determines whether an invoice should be auto-approved based on its source,
  extraction status, and the company's auto-approval setting.

  Auto-approval is opt-in per company via `auto_approve_trusted_invoices`.
  Only expense invoices with complete extraction from trusted sources qualify.
  """

  alias KsefHub.Accounts
  alias KsefHub.Companies
  alias KsefHub.Companies.Company
  alias KsefHub.Invoices.Invoice

  @doc """
  Returns `true` if the invoice should be automatically approved.

  ## Options

    * `:sender_email` — required for `:email` source invoices to verify
      that the sender is a registered platform user with active membership
      in the company.
  """
  @spec should_auto_approve?(Company.t(), Invoice.t(), keyword()) :: boolean()
  def should_auto_approve?(company, invoice, opts \\ [])

  def should_auto_approve?(%Company{auto_approve_trusted_invoices: false}, _invoice, _opts),
    do: false

  def should_auto_approve?(_company, %Invoice{type: type}, _opts) when type != :expense,
    do: false

  def should_auto_approve?(_company, %Invoice{extraction_status: status}, _opts)
      when status in [:partial, :failed],
      do: false

  def should_auto_approve?(_company, %Invoice{source: :ksef}, _opts), do: false

  def should_auto_approve?(_company, %Invoice{source: source}, _opts)
      when source in [:manual, :pdf_upload],
      do: true

  def should_auto_approve?(company, %Invoice{source: :email}, opts) do
    sender_is_company_member?(opts[:sender_email], company.id)
  end

  def should_auto_approve?(_company, _invoice, _opts), do: false

  @spec sender_is_company_member?(String.t() | nil, Ecto.UUID.t()) :: boolean()
  defp sender_is_company_member?(nil, _company_id), do: false
  defp sender_is_company_member?("", _company_id), do: false

  defp sender_is_company_member?(email, company_id) do
    with %{id: user_id} <- Accounts.get_user_by_email(email),
         %{} <- Companies.get_membership(user_id, company_id) do
      true
    else
      _ -> false
    end
  end
end
