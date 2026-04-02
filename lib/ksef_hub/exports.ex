defmodule KsefHub.Exports do
  @moduledoc """
  The Exports context. Manages bulk invoice export batches, including ZIP generation
  with PDF files and CSV summary.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Exports.{CsvBuilder, ExportBatch, ExportWorker, InvoiceDownload, ZipBuilder}
  alias KsefHub.Files
  alias KsefHub.Invoices.Invoice
  alias KsefHub.Repo

  # --- Public API ---

  @doc """
  Creates an export batch and enqueues the worker to generate the ZIP.

  ## Parameters
    * `user_id` - the requesting user's ID
    * `company_id` - the company to export invoices for
    * `params` - map with :date_from, :date_to, optional :invoice_type, :only_new
  """
  @spec create_export(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, ExportBatch.t()} | {:error, Ecto.Changeset.t()}
  def create_export(user_id, company_id, params) do
    changeset =
      %ExportBatch{}
      |> Ecto.Changeset.change(%{user_id: user_id, company_id: company_id})
      |> ExportBatch.changeset(params)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:batch, changeset)
    |> Ecto.Multi.run(:job, fn _repo, %{batch: batch} -> enqueue_worker(batch) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{batch: batch}} -> {:ok, batch}
      {:error, :batch, changeset, _} -> {:error, changeset}
      {:error, :job, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Generates the export: loads invoices, builds PDFs, creates CSV + ZIP, stores file,
  records downloads, and updates the batch.

  Called by ExportWorker.
  """
  @spec generate_export(ExportBatch.t()) :: :ok | {:error, term()}
  def generate_export(%ExportBatch{} = batch) do
    batch = Repo.preload(batch, [:user])

    with {:ok, batch} <- mark_processing(batch),
         invoices <- list_exportable_invoices(batch),
         {pdf_files, errors} <- resolve_pdfs(invoices),
         csv_binary <- CsvBuilder.build(invoices),
         {:ok, zip_binary} <- ZipBuilder.build(pdf_files, csv_binary, errors: errors),
         {:ok, file} <- store_zip_file(batch, zip_binary),
         {:ok, _batch} <- finalize_batch(batch, file.id, invoices) do
      broadcast_status(batch.company_id, batch.id, :completed)
      :ok
    else
      {:error, :already_processing} ->
        {:error, :already_processing}

      {:error, reason} ->
        fail_batch(batch, inspect(reason, limit: 500))
        broadcast_status(batch.company_id, batch.id, :failed)
        {:error, reason}
    end
  end

  @doc """
  Returns a list of invoices matching the export batch filters.

  Includes all approved invoices (including ones marked as excluded —
  the excluded flag is for analytics only, not for export filtering).
  """
  @spec list_exportable_invoices(ExportBatch.t()) :: [Invoice.t()]
  def list_exportable_invoices(%ExportBatch{} = batch) do
    batch
    |> exportable_invoices_query()
    |> order_by([i], asc: i.issue_date, asc: i.invoice_number)
    |> preload([:category, :xml_file, :pdf_file, :created_by, :inbound_email])
    |> Repo.all()
  end

  @doc "Counts invoices matching the given export filters without loading them."
  @spec count_exportable_invoices(Ecto.UUID.t(), map()) :: non_neg_integer()
  def count_exportable_invoices(company_id, filters) do
    filters
    |> to_filter_struct(company_id)
    |> exportable_invoices_query()
    |> Repo.aggregate(:count)
  end

  @doc "Lists recent export batches for a user within a company."
  @spec list_batches(Ecto.UUID.t(), Ecto.UUID.t()) :: [ExportBatch.t()]
  def list_batches(company_id, user_id) do
    ExportBatch
    |> where([b], b.company_id == ^company_id and b.user_id == ^user_id)
    |> order_by([b], desc: b.inserted_at)
    |> limit(20)
    |> Repo.all()
  end

  @doc "Fetches a batch with its zip file preloaded, scoped to a company and user."
  @spec get_batch_with_file!(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: ExportBatch.t()
  def get_batch_with_file!(company_id, user_id, batch_id) do
    ExportBatch
    |> where([b], b.company_id == ^company_id and b.user_id == ^user_id and b.id == ^batch_id)
    |> preload([:zip_file])
    |> Repo.one!()
  end

  # --- Private ---

  @spec enqueue_worker(ExportBatch.t()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  defp enqueue_worker(batch) do
    %{export_batch_id: batch.id}
    |> ExportWorker.new()
    |> Oban.insert()
  end

  @spec mark_processing(ExportBatch.t()) :: {:ok, ExportBatch.t()} | {:error, term()}
  defp mark_processing(batch) do
    {count, _} =
      ExportBatch
      |> where([b], b.id == ^batch.id and b.status == :pending)
      |> Repo.update_all(set: [status: :processing, updated_at: DateTime.utc_now()])

    if count == 1 do
      {:ok, %{batch | status: :processing}}
    else
      {:error, :already_processing}
    end
  end

  @spec finalize_batch(ExportBatch.t(), Ecto.UUID.t(), [Invoice.t()]) ::
          {:ok, ExportBatch.t()} | {:error, term()}
  defp finalize_batch(batch, zip_file_id, invoices) do
    Repo.transaction(fn ->
      changeset =
        ExportBatch.status_changeset(batch, %{
          status: :completed,
          zip_file_id: zip_file_id,
          invoice_count: length(invoices)
        })

      case Repo.update(changeset) do
        {:ok, updated_batch} ->
          do_record_downloads(batch, invoices)
          updated_batch

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @spec fail_batch(ExportBatch.t(), String.t()) ::
          {:ok, ExportBatch.t()} | {:error, Ecto.Changeset.t()}
  defp fail_batch(batch, error_message) do
    batch
    |> ExportBatch.status_changeset(%{status: :failed, error_message: error_message})
    |> Repo.update()
  end

  @spec resolve_pdfs([Invoice.t()]) :: {[{String.t(), binary()}], [String.t()]}
  defp resolve_pdfs(invoices) do
    invoices
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {invoice, idx}, {files, errors} ->
      case resolve_pdf(invoice) do
        {:ok, pdf_binary} ->
          filename = build_pdf_filename(invoice, idx)
          {[{filename, pdf_binary} | files], errors}

        {:error, reason} ->
          error = "#{invoice.invoice_number || invoice.id}: #{inspect(reason)}"
          {files, [error | errors]}
      end
    end)
    |> then(fn {files, errors} -> {Enum.reverse(files), Enum.reverse(errors)} end)
  end

  @doc "Resolves PDF binary from an invoice's pdf_file or by rendering from xml_file."
  @spec resolve_pdf(Invoice.t()) :: {:ok, binary()} | {:error, term()}
  def resolve_pdf(%Invoice{pdf_file: %{content: content}}) when is_binary(content) do
    {:ok, content}
  end

  def resolve_pdf(%Invoice{xml_file: %{content: xml_content}, ksef_number: ksef_number})
      when is_binary(xml_content) do
    pdf_renderer().generate_pdf(xml_content, %{ksef_number: ksef_number})
  end

  def resolve_pdf(_invoice) do
    {:error, :no_source_content}
  end

  @spec build_pdf_filename(Invoice.t(), pos_integer()) :: String.t()
  defp build_pdf_filename(invoice, idx) do
    number =
      (invoice.invoice_number || "invoice")
      |> String.replace(~r/[^\w\.\-]/u, "_")
      |> String.slice(0, 100)

    prefix = String.pad_leading(to_string(idx), 4, "0")

    case invoice.ksef_number do
      nil ->
        "#{prefix}_#{number}.pdf"

      ksef ->
        ksef_sanitized =
          ksef
          |> String.replace(~r/[^\w\.\-]/u, "_")
          |> String.slice(0, 100)

        "#{prefix}_#{number}_#{ksef_sanitized}.pdf"
    end
  end

  @spec store_zip_file(ExportBatch.t(), binary()) ::
          {:ok, Files.File.t()} | {:error, Ecto.Changeset.t()}
  defp store_zip_file(batch, zip_binary) do
    filename = "invoices_#{batch.date_from}_#{batch.date_to}.zip"

    Files.create_export_file(%{
      content: zip_binary,
      content_type: "application/zip",
      filename: filename
    })
  end

  @spec do_record_downloads(ExportBatch.t(), [Invoice.t()]) :: :ok
  defp do_record_downloads(batch, invoices) do
    now = DateTime.utc_now()

    entries =
      Enum.map(invoices, fn invoice ->
        %{
          id: Ecto.UUID.generate(),
          invoice_id: invoice.id,
          export_batch_id: batch.id,
          user_id: batch.user_id,
          downloaded_at: now
        }
      end)

    {inserted, _} = Repo.insert_all(InvoiceDownload, entries, on_conflict: :nothing)

    if inserted != length(invoices) do
      Logger.warning(
        "Export batch #{batch.id}: recorded #{inserted}/#{length(invoices)} downloads (#{length(invoices) - inserted} duplicates skipped)"
      )
    end

    :ok
  end

  @spec exportable_invoices_query(map()) :: Ecto.Query.t()
  defp exportable_invoices_query(%{
         company_id: company_id,
         date_from: date_from,
         date_to: date_to,
         invoice_type: invoice_type,
         only_new: only_new,
         user_id: user_id
       }) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> where([i], i.status == :approved)
    |> where([i], i.issue_date >= ^date_from and i.issue_date <= ^date_to)
    |> maybe_filter_type(invoice_type)
    |> maybe_filter_only_new(only_new, user_id)
  end

  @spec to_filter_struct(map(), Ecto.UUID.t()) :: map()
  defp to_filter_struct(filters, company_id) do
    %{
      company_id: company_id,
      date_from: filters[:date_from],
      date_to: filters[:date_to],
      invoice_type: filters[:invoice_type],
      only_new: filters[:only_new],
      user_id: filters[:user_id]
    }
  end

  @spec maybe_filter_type(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, ""), do: query

  defp maybe_filter_type(query, "expense"),
    do: where(query, [i], i.type == :expense)

  defp maybe_filter_type(query, "income"),
    do: where(query, [i], i.type == :income)

  defp maybe_filter_type(query, _), do: query

  @spec maybe_filter_only_new(Ecto.Queryable.t(), boolean() | nil, Ecto.UUID.t() | nil) ::
          Ecto.Query.t()
  defp maybe_filter_only_new(query, true, user_id) when is_binary(user_id) do
    where(
      query,
      [i],
      fragment(
        "NOT EXISTS (SELECT 1 FROM invoice_downloads d WHERE d.invoice_id = ? AND d.user_id = ?)",
        i.id,
        type(^user_id, :binary_id)
      )
    )
  end

  defp maybe_filter_only_new(query, _, _), do: query

  @spec pdf_renderer() :: module()
  defp pdf_renderer do
    Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)
  end

  @spec broadcast_status(Ecto.UUID.t(), Ecto.UUID.t(), atom()) :: :ok
  defp broadcast_status(company_id, batch_id, status) do
    Phoenix.PubSub.broadcast(
      KsefHub.PubSub,
      "exports:#{company_id}",
      {:export_status, batch_id, status}
    )
  end
end
