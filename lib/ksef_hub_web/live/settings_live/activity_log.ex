defmodule KsefHubWeb.SettingsLive.ActivityLog do
  @moduledoc """
  Settings page showing the company-wide activity log.
  Restricted to admin/owner roles via `:manage_team` permission.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.ActivityLog

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Activity Log")}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    page = parse_int(params["page"], 1)
    action_prefix = params["filter"]

    result =
      ActivityLog.list_for_company(socket.assigns.current_company.id,
        page: page,
        per_page: 50,
        action_prefix: action_prefix
      )

    {:noreply,
     assign(socket,
       entries: result.entries,
       page: result.page,
       total_pages: result.total_pages,
       total_count: result.total_count,
       filter: action_prefix
     )}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Activity Log
        <:subtitle>Company-wide audit trail of all operations</:subtitle>
      </.header>

      <div class="mt-4 flex items-center gap-2 flex-wrap">
        <.link
          :for={
            {label, value} <- [
              {"All", nil},
              {"Invoices", "invoice"},
              {"Payments", "payment_request"},
              {"Team", "team"},
              {"Categories", "category"},
              {"Credentials", "credential"},
              {"Tokens", "api_token"},
              {"Sync", "sync"},
              {"Bank Accounts", "bank_account"},
              {"Auth", "user"},
              {"Exports", "export"}
            ]
          }
          patch={filter_path(@current_company.id, value, @page)}
          class={[
            "px-2.5 py-1 text-xs rounded-md border transition-colors",
            if(@filter == value,
              do: "bg-shad-primary text-shad-primary-foreground border-shad-primary",
              else: "text-muted-foreground border-border hover:bg-shad-accent"
            )
          ]}
        >
          {label}
        </.link>
      </div>

      <div class="mt-4">
        <div :if={@entries == []} class="text-sm text-muted-foreground italic py-8 text-center">
          No activity recorded yet
        </div>

        <.table :if={@entries != []} rows={@entries} id="activity-log-table">
          <:col :let={entry} label="Time">
            <span class="text-xs text-muted-foreground whitespace-nowrap">
              {format_datetime(entry.inserted_at)}
            </span>
          </:col>
          <:col :let={entry} label="Actor">
            <span class="text-sm font-medium">{entry.actor_label || "System"}</span>
            <span
              :if={entry.actor_type != :user}
              class="ml-1 text-xs px-1 py-0.5 rounded bg-shad-accent text-shad-accent-foreground"
            >
              {entry.actor_type}
            </span>
          </:col>
          <:col :let={entry} label="Action">
            <span class="text-sm">{describe_action(entry)}</span>
            <div :if={detail = describe_details(entry)} class="text-xs text-muted-foreground mt-0.5">
              {detail}
            </div>
          </:col>
          <:col :let={entry} label="Resource">
            <.resource_link entry={entry} company_id={@current_company.id} />
          </:col>
        </.table>

        <div :if={@total_pages > 1} class="flex items-center justify-between mt-4">
          <span class="text-sm text-muted-foreground">
            Page {@page} of {@total_pages} ({@total_count} entries)
          </span>
          <div class="flex gap-2">
            <.link
              :if={@page > 1}
              patch={page_path(@current_company.id, @filter, @page - 1)}
              class="text-sm px-3 py-1 border border-border rounded-md hover:bg-shad-accent transition-colors"
            >
              Previous
            </.link>
            <.link
              :if={@page < @total_pages}
              patch={page_path(@current_company.id, @filter, @page + 1)}
              class="text-sm px-3 py-1 border border-border rounded-md hover:bg-shad-accent transition-colors"
            >
              Next
            </.link>
          </div>
        </div>
      </div>
    </.settings_layout>
    """
  end

  # ---------------------------------------------------------------------------
  # Resource links
  # ---------------------------------------------------------------------------

  attr :entry, :map, required: true
  attr :company_id, :string, required: true

  @spec resource_link(map()) :: Phoenix.LiveView.Rendered.t()
  defp resource_link(assigns) do
    assigns = assign(assigns, :href, resource_href(assigns.entry, assigns.company_id))

    ~H"""
    <.link :if={@href} navigate={@href} class="text-xs text-shad-primary hover:underline">
      {resource_label(@entry)}
    </.link>
    <span :if={!@href} class="text-xs text-muted-foreground">
      {resource_label(@entry)}
    </span>
    """
  end

  @spec resource_href(map(), String.t()) :: String.t() | nil
  defp resource_href(%{resource_type: "invoice", resource_id: id}, cid) when is_binary(id) do
    ~p"/c/#{cid}/invoices/#{id}"
  end

  defp resource_href(%{resource_type: "payment_request", resource_id: rid}, cid)
       when is_binary(rid) and rid != "" do
    ~p"/c/#{cid}/payment-requests/#{rid}/edit"
  end

  defp resource_href(%{resource_type: "payment_request", metadata: meta}, cid) do
    case meta do
      %{"invoice_id" => iid} when is_binary(iid) -> ~p"/c/#{cid}/invoices/#{iid}"
      _ -> nil
    end
  end

  defp resource_href(%{resource_type: "credential"}, cid) do
    ~p"/c/#{cid}/settings/certificates"
  end

  defp resource_href(%{resource_type: "api_token"}, cid) do
    ~p"/c/#{cid}/settings/tokens"
  end

  defp resource_href(%{resource_type: "category"}, cid) do
    ~p"/c/#{cid}/settings/categories"
  end

  defp resource_href(%{resource_type: "invitation", resource_id: id}, cid) when is_binary(id) do
    ~p"/c/#{cid}/settings/team/invitations/#{id}"
  end

  defp resource_href(%{resource_type: "company_bank_account"}, cid) do
    ~p"/c/#{cid}/settings/bank-accounts"
  end

  defp resource_href(%{resource_type: "export"}, cid) do
    ~p"/c/#{cid}/settings/exports"
  end

  defp resource_href(_entry, _cid), do: nil

  @spec resource_label(map()) :: String.t()
  defp resource_label(%{resource_type: type}) when is_binary(type) do
    type |> String.replace("_", " ") |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp resource_label(_entry), do: "—"

  # ---------------------------------------------------------------------------
  # Action descriptions (human-readable action names)
  # ---------------------------------------------------------------------------

  @static_descriptions %{
    "invoice.created" => "Created invoice",
    "invoice.excluded" => "Excluded invoice",
    "invoice.included" => "Included invoice",
    "invoice.note_updated" => "Updated note",
    "invoice.billing_date_changed" => "Changed billing period",
    "invoice.comment_added" => "Added comment",
    "invoice.comment_edited" => "Edited comment",
    "invoice.comment_deleted" => "Deleted comment",
    "invoice.public_link_generated" => "Generated public link",
    "invoice.re_extraction_triggered" => "Triggered re-extraction",
    "invoice.extraction_dismissed" => "Dismissed extraction warning",
    "credential.uploaded" => "Uploaded certificate",
    "credential.invalidated" => "Invalidated certificate",
    "payment_request.created" => "Created payment request",
    "payment_request.paid" => "Marked payment as paid",
    "payment_request.voided" => "Voided payment request",
    "payment_request.updated" => "Updated payment request",
    "sync.triggered" => "Triggered sync",
    "export.created" => "Created export",
    "export.downloaded" => "Downloaded export",
    "user.logged_in" => "Logged in",
    "user.logged_out" => "Logged out"
  }

  @spec describe_action(map()) :: String.t()
  defp describe_action(%{action: action, metadata: metadata}) do
    case Map.fetch(@static_descriptions, action) do
      {:ok, desc} -> desc
      :error -> describe_dynamic_action(action, metadata)
    end
  end

  @spec describe_dynamic_action(String.t(), map()) :: String.t()
  defp describe_dynamic_action("invoice.status_changed", metadata) do
    "Changed status to #{metadata["new_status"] || "unknown"}"
  end

  defp describe_dynamic_action("invoice.classification_changed", metadata) do
    field = metadata["field"] || "classification"

    case {metadata["old_name"], metadata["new_name"]} do
      {old, new} when is_binary(old) and is_binary(new) ->
        "Changed #{field} from #{old} to #{new}"

      {nil, new} when is_binary(new) ->
        "Set #{field} to #{new}"

      {old, nil} when is_binary(old) ->
        "Removed #{field} #{old}"

      _ ->
        "Updated #{field}"
    end
  end

  defp describe_dynamic_action("invoice.access_changed", metadata) do
    "Changed access to #{metadata["change_type"] || "restricted"}"
  end

  defp describe_dynamic_action("invoice.access_granted", _metadata) do
    "Granted invoice access"
  end

  defp describe_dynamic_action("invoice.access_revoked", _metadata) do
    "Revoked invoice access"
  end

  defp describe_dynamic_action("invoice.downloaded", metadata) do
    "Downloaded #{metadata["format"] || "file"}"
  end

  defp describe_dynamic_action("invoice.duplicate_confirmed", _metadata) do
    "Confirmed duplicate"
  end

  defp describe_dynamic_action("invoice.duplicate_dismissed", _metadata) do
    "Dismissed duplicate"
  end

  defp describe_dynamic_action("invoice.duplicate_detected", _metadata) do
    "Duplicate detected"
  end

  defp describe_dynamic_action("invoice.updated", metadata) do
    case metadata["changed_fields"] do
      fields when is_list(fields) and fields != [] ->
        humanized = Enum.map_join(fields, ", ", &String.replace(&1, "_", " "))

        "Updated #{humanized}"

      _ ->
        "Updated invoice"
    end
  end

  defp describe_dynamic_action("sync.completed", _metadata) do
    "Sync completed"
  end

  defp describe_dynamic_action("api_token.generated", metadata) do
    case metadata["token_name"] do
      name when is_binary(name) -> "Generated token \"#{name}\""
      _ -> "Generated API token"
    end
  end

  defp describe_dynamic_action("api_token.revoked", metadata) do
    case metadata["token_name"] do
      name when is_binary(name) -> "Revoked token \"#{name}\""
      _ -> "Revoked API token"
    end
  end

  defp describe_dynamic_action("team.role_changed", metadata) do
    case {metadata["old_role"], metadata["new_role"]} do
      {old, new} when is_binary(old) and is_binary(new) -> "Changed role from #{old} to #{new}"
      _ -> "Changed team role"
    end
  end

  defp describe_dynamic_action("team.member_removed", _metadata), do: "Removed team member"
  defp describe_dynamic_action("team.member_blocked", _metadata), do: "Blocked team member"
  defp describe_dynamic_action("team.member_unblocked", _metadata), do: "Unblocked team member"

  defp describe_dynamic_action("team.invitation_sent", metadata) do
    case metadata["email"] do
      email when is_binary(email) -> "Sent invitation to #{email}"
      _ -> "Sent invitation"
    end
  end

  defp describe_dynamic_action("team.invitation_accepted", metadata) do
    case metadata["email"] do
      email when is_binary(email) -> "Invitation accepted by #{email}"
      _ -> "Invitation accepted"
    end
  end

  defp describe_dynamic_action("category.created", metadata) do
    case metadata["name"] do
      name when is_binary(name) -> "Created category \"#{name}\""
      _ -> "Created category"
    end
  end

  defp describe_dynamic_action("category.updated", metadata) do
    case metadata["name"] do
      name when is_binary(name) -> "Updated category \"#{name}\""
      _ -> "Updated category"
    end
  end

  defp describe_dynamic_action("category.deleted", metadata) do
    case metadata["name"] do
      name when is_binary(name) -> "Deleted category \"#{name}\""
      _ -> "Deleted category"
    end
  end

  defp describe_dynamic_action("bank_account.created", metadata) do
    case metadata["label"] do
      label when is_binary(label) -> "Created bank account \"#{label}\""
      _ -> "Created bank account"
    end
  end

  defp describe_dynamic_action("bank_account.updated", metadata) do
    case metadata["label"] do
      label when is_binary(label) -> "Updated bank account \"#{label}\""
      _ -> "Updated bank account"
    end
  end

  defp describe_dynamic_action("bank_account.deleted", metadata) do
    case metadata["label"] do
      label when is_binary(label) -> "Deleted bank account \"#{label}\""
      _ -> "Deleted bank account"
    end
  end

  defp describe_dynamic_action(action, _metadata) do
    action
    |> String.replace(".", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # ---------------------------------------------------------------------------
  # Detail line — extra metadata shown below the action
  # ---------------------------------------------------------------------------

  @spec describe_details(map()) :: String.t() | nil
  defp describe_details(%{action: "invoice.status_changed", metadata: meta}) do
    case meta["old_status"] do
      old when is_binary(old) -> "was #{old}"
      _ -> nil
    end
  end

  defp describe_details(%{action: "invoice.created", metadata: meta}) do
    case meta["source"] do
      source when is_binary(source) -> "via #{source}"
      _ -> nil
    end
  end

  defp describe_details(%{action: "invoice.classification_changed", metadata: meta}) do
    case meta["field"] do
      "tags" ->
        old_tags = meta["old_value"] || []
        new_tags = meta["new_value"] || []
        format_tag_change(old_tags, new_tags)

      # "cost_line" kept for backward compatibility with historical activity log records
      field when field in ["cost_line", "expense_cost_line"] ->
        format_value_change(meta["old_value"], meta["new_value"])

      "project_tag" ->
        format_value_change(meta["old_value"], meta["new_value"])

      _ ->
        nil
    end
  end

  defp describe_details(%{action: "sync.completed", metadata: meta}) do
    parts =
      [
        if(meta["new_invoices"], do: "#{meta["new_invoices"]} new"),
        if(meta["updated_invoices"], do: "#{meta["updated_invoices"]} updated")
      ]
      |> Enum.reject(&is_nil/1)

    if parts != [], do: Enum.join(parts, ", "), else: nil
  end

  defp describe_details(%{action: "team.invitation_sent", metadata: meta}) do
    case meta["role"] do
      role when is_binary(role) -> "as #{role}"
      _ -> nil
    end
  end

  defp describe_details(_entry), do: nil

  @spec format_tag_change(list(), list()) :: String.t() | nil
  defp format_tag_change(old_tags, new_tags) when is_list(old_tags) and is_list(new_tags) do
    added = new_tags -- old_tags
    removed = old_tags -- new_tags

    parts =
      [
        if(added != [], do: "added: #{Enum.join(added, ", ")}"),
        if(removed != [], do: "removed: #{Enum.join(removed, ", ")}")
      ]
      |> Enum.reject(&is_nil/1)

    if parts != [], do: Enum.join(parts, "; "), else: nil
  end

  defp format_tag_change(_, _), do: nil

  @spec format_value_change(term(), term()) :: String.t() | nil
  defp format_value_change(old, new) do
    old_str = if old not in [nil, ""], do: to_string(old)
    new_str = if new not in [nil, ""], do: to_string(new)

    case {old_str, new_str} do
      {nil, nil} -> nil
      {nil, new_s} -> "set to #{new_s}"
      {old_s, nil} -> "was #{old_s}"
      {old_s, new_s} -> "#{old_s} → #{new_s}"
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  @spec format_datetime(NaiveDateTime.t()) :: String.t()
  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @spec filter_path(String.t(), String.t() | nil, pos_integer()) :: String.t()
  defp filter_path(company_id, nil, _page) do
    ~p"/c/#{company_id}/settings/activity-log"
  end

  defp filter_path(company_id, filter, _page) do
    ~p"/c/#{company_id}/settings/activity-log?filter=#{filter}"
  end

  @spec page_path(String.t(), String.t() | nil, pos_integer()) :: String.t()
  defp page_path(company_id, nil, page) do
    ~p"/c/#{company_id}/settings/activity-log?page=#{page}"
  end

  defp page_path(company_id, filter, page) do
    ~p"/c/#{company_id}/settings/activity-log?filter=#{filter}&page=#{page}"
  end

  @spec parse_int(String.t() | nil, integer()) :: integer()
  defp parse_int(nil, default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end
end
