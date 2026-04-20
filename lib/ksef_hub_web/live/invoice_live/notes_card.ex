defmodule KsefHubWeb.InvoiceLive.NotesCard do
  @moduledoc """
  Notes-tab UI for the invoice show page.

  Stateless: the parent LiveView owns `editing_note`, `note_form`, and the
  `edit_note` / `save_note` / `cancel_note` events. This module only renders.

  Three visual states:

    * no note + not editing → empty state with "Add note" CTA (if allowed)
    * editing → textarea + Save/Cancel
    * has note + not editing → note body + inline "Edit" button
  """

  use Phoenix.Component

  alias KsefHub.Invoices.Invoice

  import KsefHubWeb.CoreComponents, only: [button: 1, card: 1, empty_state: 1, icon: 1]

  attr :invoice, :map, required: true
  attr :editing_note, :boolean, required: true
  attr :note_form, :map, required: true
  attr :can_mutate, :boolean, required: true

  @spec notes_card(map()) :: Phoenix.LiveView.Rendered.t()
  def notes_card(assigns) do
    ~H"""
    <.card padding="p-0">
      <.empty_state
        :if={!Invoice.has_note?(@invoice) && !@editing_note}
        icon="hero-document-text"
        title="No notes yet"
        description="Notes are private to your team. Use them to record decisions or context."
      >
        <:action :if={@can_mutate}>
          <.button type="button" size="sm" phx-click="edit_note">
            <.icon name="hero-plus" class="size-4" /> Add note
          </.button>
        </:action>
      </.empty_state>

      <div :if={@editing_note} class="p-4">
        <.form for={@note_form} phx-submit="save_note" class="space-y-2">
          <textarea
            name={@note_form[:note].name}
            class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            rows="8"
            placeholder="Add a note..."
            id="note-textarea"
            autofocus
          >{@note_form[:note].value}</textarea>
          <div class="flex gap-2">
            <.button type="submit" size="sm">Save</.button>
            <.button type="button" variant="ghost" size="sm" phx-click="cancel_note">
              Cancel
            </.button>
          </div>
        </.form>
      </div>

      <div :if={Invoice.has_note?(@invoice) && !@editing_note} class="p-4">
        <div class="flex items-start justify-between gap-3 mb-2">
          <h2 class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Note
          </h2>
          <.button
            :if={@can_mutate}
            variant="outline"
            size="sm"
            phx-click="edit_note"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </div>
        <div
          class={[
            "text-sm whitespace-pre-line rounded p-1 -m-1",
            @can_mutate && "cursor-pointer hover:bg-muted"
          ]}
          phx-click={if(@can_mutate, do: "edit_note")}
        >
          {@invoice.note}
        </div>
      </div>
    </.card>
    """
  end
end
