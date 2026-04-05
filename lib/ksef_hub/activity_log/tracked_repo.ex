defmodule KsefHub.ActivityLog.TrackedRepo do
  @moduledoc """
  Wraps `Repo.insert/update/delete` with automatic activity log event emission.

  Use this instead of calling `Repo` directly in context functions to ensure
  every mutation is tracked. The action name and metadata are explicit —
  there's no magic inference.

  ## Usage

      # Instead of:
      invoice
      |> Invoice.changeset(%{status: :approved})
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          Events.invoice_status_changed(updated, ...)
          {:ok, updated}
        error -> error
      end

      # Write:
      invoice
      |> Invoice.changeset(%{status: :approved})
      |> TrackedRepo.update("invoice.status_changed", opts,
        old_status: to_string(invoice.status),
        new_status: "approved"
      )

  ## When NOT to use

  - Read-only queries (`Repo.all`, `Repo.one`, `Repo.get`) — no mutation, no event
  - `Repo.update_all` / bulk operations — use `Events.emit/1` directly
  - Internal helper updates (e.g., `update_last_sync`) that don't need audit trail —
    use `Repo` directly and add a comment: `# no activity event: internal bookkeeping`
  """

  alias KsefHub.ActivityLog.{Event, Events}
  alias KsefHub.Repo

  @doc """
  Inserts a changeset and emits an activity event on success.

  The `resource_type` and `company_id` are extracted from the inserted struct
  via `resource_info/1`.
  """
  @spec insert(Ecto.Changeset.t(), String.t(), keyword(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def insert(changeset, action, opts \\ [], extra_metadata \\ []) do
    case Repo.insert(changeset) do
      {:ok, struct} ->
        emit_event(action, struct, opts, extra_metadata)
        {:ok, struct}

      error ->
        error
    end
  end

  @doc """
  Updates a changeset and emits an activity event on success.

  Skips event emission if the changeset has no changes (no-op detection).
  """
  @spec update(Ecto.Changeset.t(), String.t(), keyword(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def update(changeset, action, opts \\ [], extra_metadata \\ []) do
    if changeset.changes == %{} do
      Repo.update(changeset)
    else
      case Repo.update(changeset) do
        {:ok, struct} ->
          emit_event(action, struct, opts, extra_metadata)
          {:ok, struct}

        error ->
          error
      end
    end
  end

  @doc """
  Deletes a struct and emits an activity event on success.
  """
  @spec delete(Ecto.Schema.t(), String.t(), keyword(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(struct, action, opts \\ [], extra_metadata \\ []) do
    case Repo.delete(struct) do
      {:ok, deleted} ->
        emit_event(action, deleted, opts, extra_metadata)
        {:ok, deleted}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @spec emit_event(String.t(), Ecto.Schema.t(), keyword(), keyword()) :: :ok
  defp emit_event(action, struct, opts, extra_metadata) do
    {resource_type, resource_id, company_id} = resource_info(struct)

    Events.emit(%Event{
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      company_id: company_id,
      user_id: stringify(Keyword.get(opts, :user_id)),
      actor_type: Keyword.get(opts, :actor_type, "user"),
      actor_label: Keyword.get(opts, :actor_label),
      ip_address: Keyword.get(opts, :ip_address),
      metadata: Map.new(extra_metadata)
    })
  end

  @spec resource_info(Ecto.Schema.t()) :: {String.t(), String.t() | nil, String.t() | nil}
  defp resource_info(struct) do
    resource_type =
      struct.__struct__
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    resource_id = stringify(Map.get(struct, :id))
    company_id = stringify(Map.get(struct, :company_id))

    {resource_type, resource_id, company_id}
  end

  @spec stringify(term()) :: String.t() | nil
  defp stringify(nil), do: nil
  defp stringify(val) when is_binary(val), do: val
  defp stringify(val), do: to_string(val)
end
