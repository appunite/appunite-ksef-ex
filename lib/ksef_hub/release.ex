defmodule KsefHub.Release do
  @moduledoc """
  Release tasks for running migrations in production.

  Mix is not available in production releases, so these functions
  provide the same functionality via `bin/ksef_hub eval`.

  ## Examples

      bin/ksef_hub eval "KsefHub.Release.migrate()"
      bin/ksef_hub eval "KsefHub.Release.rollback(KsefHub.Repo, 20240101000000)"
  """

  @app :ksef_hub

  @doc """
  Runs all pending Ecto migrations.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Rolls back migrations to the given `version`.
  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @reparse_fields ~w(
    seller_nip seller_name buyer_nip buyer_name invoice_number
    issue_date sales_date net_amount gross_amount currency
    purchase_order iban seller_address buyer_address
    extraction_status due_date billing_date_from billing_date_to
  )a

  @doc """
  Re-parses all KSeF invoices from their stored FA(3) XML files.

  Useful after parser improvements to backfill existing invoices.

  ## Examples

      bin/ksef_hub eval "KsefHub.Release.reparse_ksef_invoices()"
      bin/ksef_hub eval "KsefHub.Release.reparse_ksef_invoices(dry_run: true)"
      bin/ksef_hub eval "KsefHub.Release.reparse_ksef_invoices(company_id: \\"bb524c06-...\\\")"
  """
  @allowed_reparse_opts ~w(dry_run company_id invoice_id)a

  @spec reparse_ksef_invoices(keyword()) :: :ok
  def reparse_ksef_invoices(opts \\ []) do
    unknown = Keyword.keys(opts) -- @allowed_reparse_opts

    if unknown != [] do
      raise ArgumentError,
            "unknown options: #{inspect(unknown)}. Allowed: #{inspect(@allowed_reparse_opts)}"
    end

    start_app()

    dry_run? = Keyword.get(opts, :dry_run, false)
    invoices = load_ksef_invoices(opts)

    IO.puts(
      "#{if dry_run?, do: "Dry run: ", else: ""}Re-parsing #{length(invoices)} invoice(s)..."
    )

    results = Enum.map(invoices, &do_reparse_invoice(&1, dry_run?))
    Enum.zip(invoices, results) |> Enum.each(&log_reparse_result(&1, dry_run?))

    changed = Enum.count(results, &match?({:changed, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))

    unchanged = length(invoices) - changed - errors
    IO.puts("\nDone. #{changed} changed, #{unchanged} unchanged, #{errors} error(s).")

    if errors > 0 do
      raise "reparse completed with #{errors} error(s)"
    end

    :ok
  end

  @spec load_ksef_invoices(keyword()) :: [KsefHub.Invoices.Invoice.t()]
  defp load_ksef_invoices(opts) do
    import Ecto.Query

    query =
      from(i in KsefHub.Invoices.Invoice,
        where: i.source == :ksef and not is_nil(i.xml_file_id),
        order_by: [desc: i.inserted_at]
      )

    query = if id = opts[:company_id], do: where(query, [i], i.company_id == ^id), else: query
    query = if id = opts[:invoice_id], do: where(query, [i], i.id == ^id), else: query

    KsefHub.Repo.all(query)
  end

  @spec log_reparse_result({KsefHub.Invoices.Invoice.t(), term()}, boolean()) :: :ok
  defp log_reparse_result({_invoice, :unchanged}, _dry_run?), do: :ok

  defp log_reparse_result({invoice, {:changed, diff}}, dry_run?) do
    label = if dry_run?, do: "would change", else: "updated"
    IO.puts("  #{invoice.id} (#{invoice.invoice_number}) #{label}: #{Enum.join(diff, ", ")}")
  end

  defp log_reparse_result({invoice, {:error, %Ecto.Changeset{} = cs}}, _dry_run?) do
    errors =
      Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    IO.puts("  #{invoice.id} validation error: #{inspect(errors)}")
  end

  defp log_reparse_result({invoice, {:error, reason}}, _dry_run?) do
    IO.puts("  #{invoice.id} error: #{inspect(reason)}")
  end

  @spec do_reparse_invoice(KsefHub.Invoices.Invoice.t(), boolean()) ::
          {:changed, [atom()]} | :unchanged | {:error, term()}
  defp do_reparse_invoice(invoice, dry_run?) do
    before = Map.take(invoice, @reparse_fields)

    case run_reparse(invoice, dry_run?) do
      {:ok, updated} ->
        after_snap = Map.take(updated, @reparse_fields)

        diff =
          Enum.filter(@reparse_fields, fn f -> Map.get(before, f) != Map.get(after_snap, f) end)

        if diff == [], do: :unchanged, else: {:changed, diff}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec run_reparse(KsefHub.Invoices.Invoice.t(), boolean()) ::
          {:ok, KsefHub.Invoices.Invoice.t()} | {:error, term()}
  defp run_reparse(invoice, false), do: KsefHub.Invoices.reparse_from_stored_xml(invoice)

  defp run_reparse(invoice, true) do
    KsefHub.Repo.transaction(fn ->
      case KsefHub.Invoices.reparse_from_stored_xml(invoice, skip_emit: true) do
        {:ok, updated} -> KsefHub.Repo.rollback({:dry_run, updated})
        {:error, reason} -> KsefHub.Repo.rollback({:real_error, reason})
      end
    end)
    |> case do
      {:error, {:dry_run, updated}} -> {:ok, updated}
      {:error, {:real_error, reason}} -> {:error, reason}
    end
  end

  @spec load_app() :: :ok | {:error, term()}
  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end

  @spec start_app() :: :ok
  defp start_app do
    case Application.ensure_all_started(@app) do
      {:ok, _apps} -> :ok
      {:error, {app, reason}} -> raise "failed to start #{app}: #{inspect(reason)}"
    end
  end

  @spec repos() :: [module()]
  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
