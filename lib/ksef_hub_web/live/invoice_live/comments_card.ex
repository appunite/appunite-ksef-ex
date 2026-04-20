defmodule KsefHubWeb.InvoiceLive.CommentsCard do
  @moduledoc """
  Comments-tab UI for the invoice show page.

  Stateless: the parent LiveView owns the `submit_comment` / `edit_comment` /
  `save_comment_edit` / `cancel_comment_edit` / `delete_comment` events and the
  `editing_comment_id` / `edit_comment_form` / `comment_form` / `comment_form_key`
  assigns. This module only renders.

  Two visual states:

    * empty → centered empty state with "Write a comment" CTA that focuses the composer
    * populated → list of comments with author avatar, name, relative time, body, and
      hover-revealed edit/delete for the comment's author

  Either way the composer sits at the bottom: current-user avatar + textarea + Send.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import KsefHubWeb.CoreComponents,
    only: [avatar: 1, button: 1, card: 1, empty_state: 1, icon: 1]

  @composer_id "comment-composer-body"

  attr :comments, :list, required: true
  attr :comment_form, :map, required: true
  attr :comment_form_key, :integer, required: true
  attr :editing_comment_id, :string, default: nil
  attr :edit_comment_form, :map, default: nil
  attr :current_user, :map, required: true

  @doc "Renders the comments tab card: empty state or threaded comment list plus a composer."
  @spec comments_card(map()) :: Phoenix.LiveView.Rendered.t()
  def comments_card(assigns) do
    assigns = assign(assigns, :composer_id, @composer_id)

    ~H"""
    <.card padding="p-0">
      <.empty_state
        :if={@comments == []}
        icon="hero-chat-bubble-oval-left"
        title="Start the conversation"
        description="Leave a note for your team about this invoice."
      >
        <:action>
          <.button
            type="button"
            size="sm"
            phx-click={JS.focus(to: "##{@composer_id}")}
          >
            <.icon name="hero-plus" class="size-4" /> Write a comment
          </.button>
        </:action>
      </.empty_state>

      <ul :if={@comments != []} class="divide-y divide-border">
        <li
          :for={comment <- @comments}
          id={"comment-#{comment.id}"}
          class="group flex items-start gap-3 px-4 py-3"
        >
          <.avatar user={comment.user} class="size-6 mt-0.5" />
          <div class="min-w-0 flex-1 leading-snug">
            <div class="flex items-baseline gap-2">
              <span class="text-sm font-medium">{comment.user.name || comment.user.email}</span>
              <span class="text-xs text-muted-foreground">
                {relative_time(comment.inserted_at)}
              </span>
              <div
                :if={comment.user_id == @current_user.id && @editing_comment_id != comment.id}
                class="ml-auto opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity inline-flex items-center gap-2"
              >
                <button
                  type="button"
                  phx-click="edit_comment"
                  phx-value-id={comment.id}
                  class="text-muted-foreground hover:text-foreground"
                  aria-label="Edit comment"
                >
                  <.icon name="hero-pencil-square" class="size-3.5" />
                </button>
                <button
                  type="button"
                  phx-click="delete_comment"
                  phx-value-id={comment.id}
                  data-confirm="Delete this comment?"
                  class="text-muted-foreground hover:text-shad-destructive"
                  aria-label="Delete comment"
                >
                  <.icon name="hero-trash" class="size-3.5" />
                </button>
              </div>
            </div>

            <div :if={@editing_comment_id == comment.id} class="mt-1.5">
              <.form for={@edit_comment_form} phx-submit="save_comment_edit">
                <textarea
                  name={@edit_comment_form[:body].name}
                  class="w-full rounded-md border border-input bg-background px-2 py-1 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring resize-none"
                  style="field-sizing: content"
                  rows="1"
                  oninput="this.style.height='auto';this.style.height=this.scrollHeight+'px'"
                >{@edit_comment_form[:body].value}</textarea>
                <div class="flex gap-2 mt-1">
                  <.button type="submit" size="sm">Save</.button>
                  <.button type="button" variant="ghost" size="sm" phx-click="cancel_comment_edit">
                    Cancel
                  </.button>
                </div>
              </.form>
            </div>

            <p
              :if={@editing_comment_id != comment.id}
              class="text-sm whitespace-pre-wrap text-foreground"
            >
              {comment.body}
            </p>
          </div>
        </li>
      </ul>

      <div class="flex items-center gap-2 px-3 py-3 border-t border-border">
        <.avatar user={@current_user} class="size-7" />
        <.form
          for={@comment_form}
          phx-submit="submit_comment"
          id={"comment-form-#{@comment_form_key}"}
          class="flex-1 flex items-center gap-2"
        >
          <textarea
            id={@composer_id}
            name={@comment_form[:body].name}
            placeholder="Write a comment…"
            rows="1"
            class="flex-1 resize-none rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring min-h-[38px] max-h-32"
            style="field-sizing: content"
            oninput="this.style.height='auto';this.style.height=this.scrollHeight+'px'"
          >{@comment_form[:body].value}</textarea>
          <.button type="submit" size="sm">Send</.button>
        </.form>
      </div>
    </.card>
    """
  end

  @doc ~S"Returns a short human-readable age like `just now`, `5m ago`, or a date for older entries."
  @spec relative_time(NaiveDateTime.t()) :: String.t()
  def relative_time(naive_dt) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, naive_dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(naive_dt, "%Y-%m-%d")
    end
  end
end
