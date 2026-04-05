defmodule KsefHub.ActivityLog.Events do
  @moduledoc """
  Activity log event emission.

  Most events are emitted automatically via `TrackedRepo` + `Trackable` behaviour
  on schemas. This module provides:

  1. `emit/1` — the configurable dispatch point (PubSub in prod, TestEmitter in test)
  2. Domain-specific helpers for events that can't use TrackedRepo (no changeset,
     Multi transactions, cross-entity lookups)

  ## When to use these helpers directly

  - **No Ecto changeset** — login/logout, sync triggers
  - **Multi transactions** — credential upload after `Repo.transaction`
  - **Cross-entity events** — invoice comments (need invoice's company_id)

  For all other cases, use `TrackedRepo` and implement `Trackable` on the schema.
  """

  alias KsefHub.ActivityLog.Event

  @pubsub KsefHub.PubSub
  @topic "activity_log"

  @doc """
  Emits an event through the configured emitter.

  In production, broadcasts via PubSub to the Recorder GenServer.
  In test, can be configured to send to a collecting process for synchronous assertions.

  Configure via: `config :ksef_hub, :activity_log_emitter, MyEmitter`
  The emitter must be a module implementing `emit/1` that accepts an `Event` struct.
  """
  @spec emit(Event.t()) :: :ok
  def emit(%Event{} = event) do
    case Application.get_env(:ksef_hub, :activity_log_emitter) do
      nil -> do_broadcast(event)
      emitter -> emitter.emit(event)
    end
  end

  # ---------------------------------------------------------------------------
  # Invoice comment events (cross-entity: comment needs invoice's company_id)
  # ---------------------------------------------------------------------------

  @doc "Comment was added to an invoice."
  @spec invoice_comment_added(map(), map(), keyword()) :: :ok
  def invoice_comment_added(invoice, comment, opts \\ []) do
    emit(build_invoice_event("invoice.comment_added", invoice, opts, comment_id: comment.id))
  end

  @doc "Comment was edited on an invoice."
  @spec invoice_comment_edited(map(), map(), keyword()) :: :ok
  def invoice_comment_edited(invoice, comment, opts \\ []) do
    emit(build_invoice_event("invoice.comment_edited", invoice, opts, comment_id: comment.id))
  end

  @doc "Comment was deleted from an invoice."
  @spec invoice_comment_deleted(map(), String.t(), keyword()) :: :ok
  def invoice_comment_deleted(invoice, comment_id, opts \\ []) do
    emit(build_invoice_event("invoice.comment_deleted", invoice, opts, comment_id: comment_id))
  end

  # ---------------------------------------------------------------------------
  # Invoice UI-only events (no changeset — triggered from LiveView handlers)
  # ---------------------------------------------------------------------------

  @doc "Public sharing link was generated."
  @spec invoice_public_link_generated(map(), keyword()) :: :ok
  def invoice_public_link_generated(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.public_link_generated", invoice, opts))
  end

  @doc "Invoice re-extraction was triggered."
  @spec invoice_re_extraction_triggered(map(), keyword()) :: :ok
  def invoice_re_extraction_triggered(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.re_extraction_triggered", invoice, opts))
  end

  # ---------------------------------------------------------------------------
  # Credential events (Multi transaction — insert bypasses TrackedRepo)
  # ---------------------------------------------------------------------------

  @doc "Credential was uploaded (used after Multi.insert in replace_active_credential)."
  @spec credential_uploaded(map(), keyword()) :: :ok
  def credential_uploaded(credential, opts \\ []) do
    emit(
      build_event("credential.uploaded",
        resource_type: "credential",
        resource_id: credential.id,
        company_id: Map.get(credential, :company_id),
        opts: opts
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Export events (Multi transaction)
  # ---------------------------------------------------------------------------

  @doc "Export batch was created."
  @spec export_created(map(), keyword()) :: :ok
  def export_created(export_batch, opts \\ []) do
    emit(
      build_event("export.created",
        resource_type: "export",
        resource_id: export_batch.id,
        company_id: export_batch.company_id,
        opts: opts
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Sync events (no changeset — Oban job trigger)
  # ---------------------------------------------------------------------------

  @doc "Manual sync was triggered."
  @spec sync_triggered(String.t(), keyword()) :: :ok
  def sync_triggered(company_id, opts \\ []) do
    emit(
      build_event("sync.triggered",
        resource_type: "sync",
        company_id: company_id,
        opts: opts
      )
    )
  end

  @doc "Sync completed with statistics."
  @spec sync_completed(String.t(), map(), keyword()) :: :ok
  def sync_completed(company_id, stats, opts \\ []) do
    emit(
      build_event("sync.completed",
        resource_type: "sync",
        company_id: company_id,
        opts: Keyword.merge(opts, actor_type: "system", actor_label: "KSeF Sync"),
        extra_metadata: stats
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Auth events (no Ecto changeset — session management)
  # ---------------------------------------------------------------------------

  @doc "User logged in."
  @spec user_logged_in(map(), keyword()) :: :ok
  def user_logged_in(user, opts \\ []) do
    emit(
      build_event("user.logged_in",
        resource_type: "user",
        resource_id: user.id,
        opts: Keyword.merge([user_id: user.id, actor_label: user.name || user.email], opts)
      )
    )
  end

  @doc "User logged out."
  @spec user_logged_out(map(), keyword()) :: :ok
  def user_logged_out(user, opts \\ []) do
    emit(
      build_event("user.logged_out",
        resource_type: "user",
        resource_id: user.id,
        opts: Keyword.merge([user_id: user.id, actor_label: user.name || user.email], opts)
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec build_invoice_event(String.t(), map(), keyword(), Enumerable.t()) :: Event.t()
  defp build_invoice_event(action, invoice, opts, extra_metadata \\ %{}) do
    build_event(action,
      resource_type: "invoice",
      resource_id: invoice.id,
      company_id: invoice.company_id,
      opts: opts,
      extra_metadata: extra_metadata
    )
  end

  @spec build_event(String.t(), keyword()) :: Event.t()
  defp build_event(action, params) do
    opts = Keyword.get(params, :opts, [])
    extra = params |> Keyword.get(:extra_metadata, %{}) |> Map.new()
    caller_meta = opts |> Keyword.get(:metadata, %{}) |> Map.new()

    user_id = Keyword.get(opts, :user_id)

    %Event{
      action: action,
      resource_type: Keyword.get(params, :resource_type),
      resource_id: stringify(Keyword.get(params, :resource_id)),
      company_id: stringify(Keyword.get(params, :company_id)),
      user_id: stringify(user_id),
      actor_type: Keyword.get(opts, :actor_type, if(user_id, do: "user", else: "system")),
      actor_label: Keyword.get(opts, :actor_label),
      ip_address: Keyword.get(opts, :ip_address),
      metadata: Map.merge(caller_meta, extra)
    }
  end

  @spec do_broadcast(Event.t()) :: :ok
  defp do_broadcast(%Event{} = event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:activity_event, event})
  end

  @spec stringify(term()) :: String.t() | nil
  defp stringify(nil), do: nil
  defp stringify(val) when is_binary(val), do: val
  defp stringify(val), do: to_string(val)
end
