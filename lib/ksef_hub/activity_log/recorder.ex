defmodule KsefHub.ActivityLog.Recorder do
  @moduledoc """
  GenServer that subscribes to the activity log PubSub topic and persists
  events to the audit_logs table.

  After a successful insert, broadcasts to resource-specific topics so
  LiveView components can update in real time.
  """

  use GenServer

  require Logger

  alias KsefHub.ActivityLog.Event
  alias KsefHub.AuditLog

  @pubsub KsefHub.PubSub
  @topic "activity_log"

  # --- Client API ---

  @doc "Starts the Recorder and subscribes to the activity_log PubSub topic."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    enabled = Application.get_env(:ksef_hub, :activity_log_recorder, true)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :enabled, enabled), name: __MODULE__)
  end

  # --- Server Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()} | :ignore
  def init(opts) do
    if Keyword.get(opts, :enabled, true) do
      Phoenix.PubSub.subscribe(@pubsub, @topic)
      {:ok, %{}}
    else
      :ignore
    end
  end

  @impl true
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info({:activity_event, %Event{} = event}, state) do
    try do
      case persist_event(event) do
        {:ok, audit_log} ->
          broadcast_to_resource(event, audit_log)

        {:error, changeset} ->
          Logger.warning(
            "ActivityLog.Recorder failed to persist event: #{inspect(event.action)} — #{inspect(changeset.errors)}"
          )
      end
    rescue
      error ->
        Logger.error(
          "ActivityLog.Recorder crashed persisting #{inspect(event.action)}: #{Exception.message(error)}"
        )
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  @spec persist_event(Event.t()) :: {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  defp persist_event(%Event{} = event) do
    AuditLog.log(event.action,
      resource_type: event.resource_type,
      resource_id: event.resource_id,
      company_id: event.company_id,
      user_id: event.user_id,
      actor_type: event.actor_type,
      actor_label: event.actor_label,
      metadata: event.metadata,
      ip_address: event.ip_address
    )
  end

  @spec broadcast_to_resource(Event.t(), AuditLog.t()) :: :ok
  defp broadcast_to_resource(%Event{resource_type: type, resource_id: id}, audit_log)
       when is_binary(type) and is_binary(id) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "activity:#{type}:#{id}",
      {:new_activity, audit_log}
    )
  end

  defp broadcast_to_resource(_event, _audit_log), do: :ok
end
