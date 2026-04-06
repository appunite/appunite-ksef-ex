defmodule KsefHub.ActivityLog.Event do
  @moduledoc """
  Struct representing a domain event to be recorded in the activity log.

  Events are broadcast via PubSub and persisted by the Recorder GenServer.
  """

  @actor_types [:user, :system, :api, :email]

  @type actor_type :: :user | :system | :api | :email

  @type t :: %__MODULE__{
          action: String.t(),
          resource_type: String.t() | nil,
          resource_id: String.t() | nil,
          company_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          actor_type: actor_type(),
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

  @doc "Returns the list of valid actor type atoms."
  @spec actor_types() :: [actor_type()]
  def actor_types, do: @actor_types

  @doc "Resolves actor_type from opts, defaulting based on presence of user_id."
  @spec resolve_actor_type(keyword()) :: actor_type()
  def resolve_actor_type(opts) do
    case Keyword.get(opts, :actor_type) do
      nil -> if Keyword.get(opts, :user_id), do: :user, else: :system
      type -> type
    end
  end
end
