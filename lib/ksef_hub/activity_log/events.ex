defmodule KsefHub.ActivityLog.Events do
  @moduledoc """
  Domain-specific broadcast helpers for the activity log.

  Each function constructs an `Event` struct and broadcasts it via PubSub.
  The `Recorder` GenServer subscribes and persists events to the database.

  ## Usage

  Context functions call these helpers on successful operations:

      def approve_invoice(invoice, opts \\\\ []) do
        case update_invoice(invoice, %{status: :approved}) do
          {:ok, updated} ->
            Events.invoice_status_changed(updated, :pending, :approved, opts)
            {:ok, updated}
          error -> error
        end
      end

  ## Options

  All functions accept an `opts` keyword list with:
    * `:user_id` — UUID of the acting user
    * `:actor_type` — `"user"` (default), `"system"`, or `"api"`
    * `:actor_label` — human-readable actor name
    * `:ip_address` — request IP address
    * `:metadata` — additional metadata to merge
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
  # Invoice events
  # ---------------------------------------------------------------------------

  @doc "Invoice was created (KSeF sync, manual, PDF upload, or email)."
  @spec invoice_created(map(), keyword()) :: :ok
  def invoice_created(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.created", invoice, opts, source: to_string(invoice.source)))
  end

  @doc "Invoice fields were updated."
  @spec invoice_updated(map(), map(), keyword()) :: :ok
  def invoice_updated(invoice, changed_fields, opts \\ []) do
    emit(
      build_invoice_event("invoice.updated", invoice, opts,
        changed_fields: Map.keys(changed_fields) |> Enum.map(&to_string/1)
      )
    )
  end

  @doc "Invoice status was changed (approved, rejected, reset to pending)."
  @spec invoice_status_changed(map(), atom(), atom(), keyword()) :: :ok
  def invoice_status_changed(invoice, old_status, new_status, opts \\ []) do
    emit(
      build_invoice_event("invoice.status_changed", invoice, opts,
        old_status: to_string(old_status),
        new_status: to_string(new_status)
      )
    )
  end

  @doc "Duplicate was detected for an invoice."
  @spec invoice_duplicate_detected(map(), String.t(), keyword()) :: :ok
  def invoice_duplicate_detected(invoice, duplicate_of_id, opts \\ []) do
    emit(
      build_invoice_event("invoice.duplicate_detected", invoice, opts,
        duplicate_of_id: duplicate_of_id
      )
    )
  end

  @doc "Duplicate was confirmed."
  @spec invoice_duplicate_confirmed(map(), keyword()) :: :ok
  def invoice_duplicate_confirmed(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.duplicate_confirmed", invoice, opts))
  end

  @doc "Duplicate was dismissed."
  @spec invoice_duplicate_dismissed(map(), keyword()) :: :ok
  def invoice_duplicate_dismissed(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.duplicate_dismissed", invoice, opts))
  end

  @doc "Invoice was downloaded (PDF or XML)."
  @spec invoice_downloaded(map(), String.t(), keyword()) :: :ok
  def invoice_downloaded(invoice, format, opts \\ []) do
    emit(build_invoice_event("invoice.downloaded", invoice, opts, format: format))
  end

  @doc "Invoice was excluded from reports."
  @spec invoice_excluded(map(), keyword()) :: :ok
  def invoice_excluded(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.excluded", invoice, opts))
  end

  @doc "Invoice was included back into reports."
  @spec invoice_included(map(), keyword()) :: :ok
  def invoice_included(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.included", invoice, opts))
  end

  @doc "Invoice note was updated."
  @spec invoice_note_updated(map(), keyword()) :: :ok
  def invoice_note_updated(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.note_updated", invoice, opts))
  end

  @doc "Invoice billing date was changed."
  @spec invoice_billing_date_changed(map(), keyword()) :: :ok
  def invoice_billing_date_changed(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.billing_date_changed", invoice, opts))
  end

  @doc "Invoice access control was changed."
  @spec invoice_access_changed(map(), String.t(), keyword()) :: :ok
  def invoice_access_changed(invoice, change_type, opts \\ []) do
    emit(build_invoice_event("invoice.access_changed", invoice, opts, change_type: change_type))
  end

  @doc "Public sharing link was generated."
  @spec invoice_public_link_generated(map(), keyword()) :: :ok
  def invoice_public_link_generated(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.public_link_generated", invoice, opts))
  end

  @doc "Invoice classification changed (category, tags, project_tag, cost_line)."
  @spec invoice_classification_changed(map(), map(), keyword()) :: :ok
  def invoice_classification_changed(invoice, changes, opts \\ []) do
    emit(build_invoice_event("invoice.classification_changed", invoice, opts, changes))
  end

  @doc "Invoice extraction completed or re-extraction triggered."
  @spec invoice_extraction_completed(map(), keyword()) :: :ok
  def invoice_extraction_completed(invoice, opts \\ []) do
    emit(
      build_invoice_event("invoice.extraction_completed", invoice, opts,
        extraction_status: to_string(invoice.extraction_status)
      )
    )
  end

  @doc "Invoice re-extraction was triggered."
  @spec invoice_re_extraction_triggered(map(), keyword()) :: :ok
  def invoice_re_extraction_triggered(invoice, opts \\ []) do
    emit(build_invoice_event("invoice.re_extraction_triggered", invoice, opts))
  end

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
  # Payment request events
  # ---------------------------------------------------------------------------

  @doc "Payment request was created."
  @spec payment_request_created(map(), keyword()) :: :ok
  def payment_request_created(payment_request, opts \\ []) do
    emit(
      build_event("payment_request.created",
        resource_type: "payment_request",
        resource_id: payment_request.id,
        company_id: payment_request.company_id,
        opts: opts,
        extra_metadata: %{invoice_id: payment_request.invoice_id}
      )
    )
  end

  @doc "Payment request was updated."
  @spec payment_request_updated(map(), keyword()) :: :ok
  def payment_request_updated(payment_request, opts \\ []) do
    emit(
      build_event("payment_request.updated",
        resource_type: "payment_request",
        resource_id: payment_request.id,
        company_id: payment_request.company_id,
        opts: opts
      )
    )
  end

  @doc "Payment request was marked as paid."
  @spec payment_request_paid(map(), keyword()) :: :ok
  def payment_request_paid(payment_request, opts \\ []) do
    emit(
      build_event("payment_request.paid",
        resource_type: "payment_request",
        resource_id: payment_request.id,
        company_id: payment_request.company_id,
        opts: opts,
        extra_metadata: %{invoice_id: payment_request.invoice_id}
      )
    )
  end

  @doc "Payment request was voided."
  @spec payment_request_voided(map(), keyword()) :: :ok
  def payment_request_voided(payment_request, opts \\ []) do
    emit(
      build_event("payment_request.voided",
        resource_type: "payment_request",
        resource_id: payment_request.id,
        company_id: payment_request.company_id,
        opts: opts,
        extra_metadata: %{invoice_id: payment_request.invoice_id}
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Credential / certificate events
  # ---------------------------------------------------------------------------

  @doc "Credential or certificate was uploaded."
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

  @doc "Credential was invalidated (deactivated)."
  @spec credential_invalidated(map(), keyword()) :: :ok
  def credential_invalidated(credential, opts \\ []) do
    emit(
      build_event("credential.invalidated",
        resource_type: "credential",
        resource_id: credential.id,
        company_id: Map.get(credential, :company_id),
        opts: opts
      )
    )
  end

  @doc "Credential was replaced (old deactivated, new created)."
  @spec credential_replaced(map(), map(), keyword()) :: :ok
  def credential_replaced(old_credential, new_credential, opts \\ []) do
    emit(
      build_event("credential.replaced",
        resource_type: "credential",
        resource_id: new_credential.id,
        company_id: Map.get(new_credential, :company_id),
        opts: opts,
        extra_metadata: %{replaced_credential_id: old_credential.id}
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Category events
  # ---------------------------------------------------------------------------

  @doc "Category was created."
  @spec category_created(map(), keyword()) :: :ok
  def category_created(category, opts \\ []) do
    emit(
      build_event("category.created",
        resource_type: "category",
        resource_id: category.id,
        company_id: category.company_id,
        opts: opts,
        extra_metadata: %{name: category.name, identifier: category.identifier}
      )
    )
  end

  @doc "Category was updated."
  @spec category_updated(map(), keyword()) :: :ok
  def category_updated(category, opts \\ []) do
    emit(
      build_event("category.updated",
        resource_type: "category",
        resource_id: category.id,
        company_id: category.company_id,
        opts: opts,
        extra_metadata: %{name: category.name}
      )
    )
  end

  @doc "Category was deleted."
  @spec category_deleted(map(), keyword()) :: :ok
  def category_deleted(category, opts \\ []) do
    emit(
      build_event("category.deleted",
        resource_type: "category",
        resource_id: category.id,
        company_id: category.company_id,
        opts: opts,
        extra_metadata: %{name: category.name, identifier: category.identifier}
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Export events
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
  # Sync events
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
  # Bank account events
  # ---------------------------------------------------------------------------

  @doc "Bank account was created."
  @spec bank_account_created(map(), keyword()) :: :ok
  def bank_account_created(bank_account, opts \\ []) do
    emit(
      build_event("bank_account.created",
        resource_type: "bank_account",
        resource_id: bank_account.id,
        company_id: bank_account.company_id,
        opts: opts,
        extra_metadata: %{label: bank_account.label, currency: bank_account.currency}
      )
    )
  end

  @doc "Bank account was updated."
  @spec bank_account_updated(map(), keyword()) :: :ok
  def bank_account_updated(bank_account, opts \\ []) do
    emit(
      build_event("bank_account.updated",
        resource_type: "bank_account",
        resource_id: bank_account.id,
        company_id: bank_account.company_id,
        opts: opts,
        extra_metadata: %{label: bank_account.label}
      )
    )
  end

  @doc "Bank account was deleted."
  @spec bank_account_deleted(map(), keyword()) :: :ok
  def bank_account_deleted(bank_account, opts \\ []) do
    emit(
      build_event("bank_account.deleted",
        resource_type: "bank_account",
        resource_id: bank_account.id,
        company_id: bank_account.company_id,
        opts: opts,
        extra_metadata: %{label: bank_account.label}
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Team events
  # ---------------------------------------------------------------------------

  @doc "Team member was invited."
  @spec team_member_invited(map(), keyword()) :: :ok
  def team_member_invited(membership, opts \\ []) do
    emit(
      build_event("team.member_invited",
        resource_type: "membership",
        resource_id: membership.id,
        company_id: membership.company_id,
        opts: opts,
        extra_metadata: %{
          member_user_id: membership.user_id,
          role: to_string(membership.role)
        }
      )
    )
  end

  @doc "Team member role was changed."
  @spec team_role_changed(map(), atom(), atom(), keyword()) :: :ok
  def team_role_changed(membership, old_role, new_role, opts \\ []) do
    emit(
      build_event("team.role_changed",
        resource_type: "membership",
        resource_id: membership.id,
        company_id: membership.company_id,
        opts: opts,
        extra_metadata: %{
          member_user_id: membership.user_id,
          old_role: to_string(old_role),
          new_role: to_string(new_role)
        }
      )
    )
  end

  @doc "Team member was blocked."
  @spec team_member_blocked(map(), keyword()) :: :ok
  def team_member_blocked(membership, opts \\ []) do
    emit(
      build_event("team.member_blocked",
        resource_type: "membership",
        resource_id: membership.id,
        company_id: membership.company_id,
        opts: opts,
        extra_metadata: %{member_user_id: membership.user_id}
      )
    )
  end

  @doc "Team member was unblocked."
  @spec team_member_unblocked(map(), keyword()) :: :ok
  def team_member_unblocked(membership, opts \\ []) do
    emit(
      build_event("team.member_unblocked",
        resource_type: "membership",
        resource_id: membership.id,
        company_id: membership.company_id,
        opts: opts,
        extra_metadata: %{member_user_id: membership.user_id}
      )
    )
  end

  # ---------------------------------------------------------------------------
  # API token events
  # ---------------------------------------------------------------------------

  @doc "API token was generated."
  @spec api_token_generated(map(), keyword()) :: :ok
  def api_token_generated(token, opts \\ []) do
    emit(
      build_event("api_token.generated",
        resource_type: "api_token",
        resource_id: token.id,
        company_id: Map.get(token, :company_id),
        opts: opts,
        extra_metadata: %{token_name: token.name}
      )
    )
  end

  @doc "API token was revoked."
  @spec api_token_revoked(map(), keyword()) :: :ok
  def api_token_revoked(token, opts \\ []) do
    emit(
      build_event("api_token.revoked",
        resource_type: "api_token",
        resource_id: token.id,
        company_id: Map.get(token, :company_id),
        opts: opts,
        extra_metadata: %{token_name: token.name}
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Auth events
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
    caller_meta = Keyword.get(opts, :metadata, %{})

    %Event{
      action: action,
      resource_type: Keyword.get(params, :resource_type),
      resource_id: stringify(Keyword.get(params, :resource_id)),
      company_id: stringify(Keyword.get(params, :company_id)),
      user_id: stringify(Keyword.get(opts, :user_id)),
      actor_type: Keyword.get(opts, :actor_type, "user"),
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
