defmodule KsefHub.Invoices.Duplicates do
  @moduledoc """
  Duplicate invoice management.

  Handles confirming, dismissing, and marking invoices as duplicates.
  Also provides helpers for detecting unique-constraint conflicts and
  formatting error reasons during duplicate handling.
  """

  require Logger

  alias KsefHub.ActivityLog.Event
  alias KsefHub.ActivityLog.TrackedRepo

  alias KsefHub.Invoices.{DuplicateDetector, Invoice}

  alias KsefHub.Repo

  @doc """
  Confirms a suspected duplicate invoice.

  Only valid when `duplicate_of_id` is set and `duplicate_status` is `:suspected`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not `:suspected`.
  """
  @spec confirm_duplicate(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def confirm_duplicate(invoice, opts \\ [])

  def confirm_duplicate(%Invoice{duplicate_of_id: nil}, _opts),
    do: {:error, :not_a_duplicate}

  def confirm_duplicate(%Invoice{duplicate_status: :suspected} = invoice, opts) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: :confirmed})
    |> TrackedRepo.update(opts)
  end

  def confirm_duplicate(%Invoice{}, _opts), do: {:error, :invalid_status}

  @doc """
  Dismisses a duplicate invoice.

  Valid when `duplicate_of_id` is set and `duplicate_status` is `:suspected` or `:confirmed`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not dismissable.
  """
  @spec dismiss_duplicate(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def dismiss_duplicate(invoice, opts \\ [])

  def dismiss_duplicate(%Invoice{duplicate_of_id: nil}, _opts),
    do: {:error, :not_a_duplicate}

  def dismiss_duplicate(%Invoice{duplicate_status: status} = invoice, opts)
      when status in [:suspected, :confirmed] do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: :dismissed})
    |> TrackedRepo.update(opts)
  end

  def dismiss_duplicate(%Invoice{}, _opts), do: {:error, :invalid_status}

  @doc false
  @spec mark_as_duplicate(Invoice.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  def mark_as_duplicate(invoice, original_id, opts) do
    case invoice
         |> Invoice.duplicate_changeset(%{
           duplicate_of_id: original_id,
           duplicate_status: :suspected
         })
         |> TrackedRepo.update(opts) do
      {:ok, updated} ->
        updated

      {:error, reason} ->
        Logger.warning(
          "Failed to mark invoice #{invoice.id} (company #{invoice.company_id}) " <>
            "as duplicate of #{original_id}: #{format_error_reason(reason)}"
        )

        invoice
    end
  end

  @doc false
  @spec maybe_mark_business_field_duplicate(Invoice.t(), :inserted | :updated) :: Invoice.t()
  def maybe_mark_business_field_duplicate(invoice, :updated), do: invoice

  def maybe_mark_business_field_duplicate(invoice, :inserted) do
    attrs = Map.from_struct(invoice)

    case DuplicateDetector.find_original_id(invoice.company_id, attrs, exclude_id: invoice.id) do
      nil ->
        invoice

      older_id ->
        case Repo.get(Invoice, older_id) do
          nil -> :ok
          older_invoice -> mark_as_duplicate(older_invoice, invoice.id, Event.ksef_sync_opts())
        end

        invoice
    end
  end

  @doc false
  @spec unique_ksef_number_conflict?(Ecto.Changeset.t()) :: boolean()
  def unique_ksef_number_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {:company_id, {_, [constraint: :unique, constraint_name: name]}} ->
        name == "invoices_company_id_ksef_number_unique_non_duplicate"

      _ ->
        false
    end)
  end

  @doc false
  @spec format_error_reason(term()) :: String.t()
  def format_error_reason(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> inspect()
  end

  def format_error_reason(reason), do: inspect(reason)
end
