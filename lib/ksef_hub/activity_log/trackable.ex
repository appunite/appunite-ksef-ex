defmodule KsefHub.ActivityLog.Trackable do
  @moduledoc """
  Behaviour for Ecto schemas that participate in automatic activity logging.

  Schemas implementing this behaviour define how their changesets map to
  activity events. The `TrackedRepo` wrapper calls these callbacks
  automatically — developers just use `TrackedRepo.update(changeset, opts)`
  and the schema decides what event to emit.

  ## Example

      defmodule KsefHub.Invoices.Invoice do
        @behaviour KsefHub.ActivityLog.Trackable

        @impl true
        def track_change(changeset) do
          changes = changeset.changes
          old = changeset.data

          cond do
            Map.has_key?(changes, :expense_approval_status) ->
              {"invoice.status_changed",
               %{old_status: to_string(old.expense_approval_status), new_status: to_string(changes.expense_approval_status)}}

            Map.has_key?(changes, :is_excluded) ->
              action = if changes.is_excluded, do: "invoice.excluded", else: "invoice.included"
              {action, %{}}

            true ->
              {"invoice.updated", %{changed_fields: Map.keys(changes) |> Enum.map(&to_string/1)}}
          end
        end

        @impl true
        def track_delete(_struct), do: :skip
      end

  ## Design

  The changeset carries all the information needed to classify an event:
  - `changeset.changes` — what fields changed and their new values
  - `changeset.data` — the original struct with old values
  - `changeset.action` — `:insert`, `:update`, or `:delete`

  This means the **schema owns the mapping** from data changes to domain events.
  Context functions stay clean — they build changesets and call TrackedRepo.
  No manual `Events.*` calls needed.
  """

  @doc """
  Classifies an update or insert changeset into an activity event.

  Return `{action, metadata}` to emit an event, or `:skip` to suppress.
  Called automatically by `TrackedRepo.update/2` and `TrackedRepo.insert/2`
  when the changeset has actual changes.
  """
  @callback track_change(changeset :: Ecto.Changeset.t()) ::
              {action :: String.t(), metadata :: map()} | :skip

  @doc """
  Returns the event for a delete operation.

  Return `{action, metadata}` to emit an event, or `:skip` to suppress.
  Called automatically by `TrackedRepo.delete/2`.
  """
  @callback track_delete(struct :: Ecto.Schema.t()) ::
              {action :: String.t(), metadata :: map()} | :skip

  @doc """
  Returns true if the given module implements the Trackable behaviour.
  """
  @spec trackable?(module()) :: boolean()
  def trackable?(module) do
    function_exported?(module, :track_change, 1) and function_exported?(module, :track_delete, 1)
  end
end
