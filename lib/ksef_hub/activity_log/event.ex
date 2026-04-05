defmodule KsefHub.ActivityLog.Event do
  @moduledoc """
  Struct representing a domain event to be recorded in the activity log.

  Events are broadcast via PubSub and persisted by the Recorder GenServer.
  """

  @type t :: %__MODULE__{
          action: String.t(),
          resource_type: String.t() | nil,
          resource_id: String.t() | nil,
          company_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          actor_type: String.t(),
          actor_label: String.t() | nil,
          metadata: map(),
          ip_address: String.t() | nil
        }

  @enforce_keys [:action, :actor_type]
  defstruct [
    :action,
    :resource_type,
    :resource_id,
    :company_id,
    :user_id,
    :actor_type,
    :actor_label,
    :ip_address,
    metadata: %{}
  ]
end
