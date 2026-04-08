defmodule Mix.Tasks.ReparseKsefInvoices do
  @moduledoc """
  Re-parses all KSeF invoices from their stored FA(3) XML files.

  Useful after parser improvements (e.g. new field extraction, bug fixes)
  to backfill existing invoices without a full KSeF re-sync.

  ## Usage

      # Dry run — show what would change without updating
      mix reparse_ksef_invoices --dry-run

      # Re-parse all KSeF invoices
      mix reparse_ksef_invoices

      # Re-parse invoices for a specific company
      mix reparse_ksef_invoices --company-id bb524c06-b171-4ab0-8b23-9af2443d543f

      # Re-parse a single invoice
      mix reparse_ksef_invoices --invoice-id 68cbbea5-b22d-4627-b64c-84857d48706d
  """

  use Mix.Task

  @shortdoc "Re-parses KSeF invoices from stored XML"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [dry_run: :boolean, company_id: :string, invoice_id: :string],
        aliases: [n: :dry_run]
      )

    KsefHub.Release.reparse_ksef_invoices(opts)
  end
end
