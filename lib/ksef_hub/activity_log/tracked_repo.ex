defmodule KsefHub.ActivityLog.TrackedRepo do
  @moduledoc """
  Repo wrapper with automatic activity log event emission.

  Schemas that implement `KsefHub.ActivityLog.Trackable` get automatic
  event classification — the schema inspects its own changeset and decides
  what event to emit. No manual action names needed.

  ## Usage

      # The developer just does:
      invoice
      |> Invoice.changeset(%{status: :approved})
      |> TrackedRepo.update(opts)

      # Invoice.track_change/1 sees the :status change and returns:
      # {"invoice.status_changed", %{old_status: "pending", new_status: "approved"}}

      # TrackedRepo emits the event automatically.

  ## Fallback for schemas without Trackable

  If the schema doesn't implement `Trackable`, pass the action name explicitly:

      TrackedRepo.update(changeset, opts, action: "some.action", metadata: %{...})

  ## When NOT to use

  - Read-only queries (`Repo.all`, `Repo.one`, `Repo.get`)
  - `Repo.update_all` / bulk operations — use `Events.emit/1` directly
  - Internal bookkeeping (`update_last_sync`) — use `Repo` directly
  """

  alias KsefHub.ActivityLog.{Event, Events, Trackable}
  alias KsefHub.Repo

  @doc """
  Inserts a changeset and emits an activity event on success.

  Event action and metadata are derived from `schema.track_change(changeset)`,
  or from `opts[:action]` if the schema doesn't implement `Trackable`.
  """
  @spec insert(Ecto.Changeset.t(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def insert(changeset, opts \\ []) do
    case Repo.insert(changeset) do
      {:ok, struct} ->
        maybe_emit(%{changeset | action: :insert}, struct, opts)
        {:ok, struct}

      error ->
        error
    end
  end

  @doc """
  Updates a changeset and emits an activity event on success.

  Skips event emission if the changeset has no changes (no-op detection).
  """
  @spec update(Ecto.Changeset.t(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def update(changeset, opts \\ []) do
    if changeset.changes == %{} do
      Repo.update(changeset)
    else
      case Repo.update(changeset) do
        {:ok, struct} ->
          maybe_emit(changeset, struct, opts)
          {:ok, struct}

        error ->
          error
      end
    end
  end

  @doc """
  Deletes a struct and emits an activity event on success.

  Event action and metadata are derived from `schema.track_delete(struct)`,
  or from `opts[:action]` if the schema doesn't implement `Trackable`.
  """
  @spec delete(Ecto.Schema.t(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(struct, opts \\ []) do
    case Repo.delete(struct) do
      {:ok, deleted} ->
        maybe_emit_delete(deleted, opts)
        {:ok, deleted}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @spec maybe_emit(Ecto.Changeset.t(), Ecto.Schema.t(), keyword()) :: :ok
  defp maybe_emit(changeset, struct, opts) do
    module = struct.__struct__

    event_info =
      if Trackable.trackable?(module) do
        module.track_change(changeset)
      else
        explicit_event(opts)
      end

    case event_info do
      {action, metadata} -> emit_event(action, struct, opts, metadata)
      :skip -> :ok
    end
  end

  @spec maybe_emit_delete(Ecto.Schema.t(), keyword()) :: :ok
  defp maybe_emit_delete(struct, opts) do
    module = struct.__struct__

    event_info =
      if Trackable.trackable?(module) and function_exported?(module, :track_delete, 1) do
        module.track_delete(struct)
      else
        explicit_event(opts)
      end

    case event_info do
      {action, metadata} -> emit_event(action, struct, opts, metadata)
      :skip -> :ok
    end
  end

  @spec explicit_event(keyword()) :: {String.t(), map()} | :skip
  defp explicit_event(opts) do
    case Keyword.get(opts, :action) do
      nil -> :skip
      action -> {action, Keyword.get(opts, :metadata, %{}) |> Map.new()}
    end
  end

  @spec emit_event(String.t(), Ecto.Schema.t(), keyword(), map()) :: :ok
  defp emit_event(action, struct, opts, extra_metadata) do
    {resource_type, resource_id, company_id} = resource_info(struct)

    user_id = Keyword.get(opts, :user_id)

    Events.emit(%Event{
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      company_id: company_id,
      user_id: stringify(user_id),
      actor_type: Event.resolve_actor_type(opts),
      actor_label: Keyword.get(opts, :actor_label),
      ip_address: Keyword.get(opts, :ip_address),
      metadata: extra_metadata
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
