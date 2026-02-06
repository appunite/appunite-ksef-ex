defmodule KsefHub.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias KsefHub.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}
    field :ip_address, :string

    belongs_to :user, KsefHub.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:action, :resource_type, :resource_id, :metadata, :user_id, :ip_address])
    |> validate_required([:action])
  end

  @doc """
  Creates an audit log entry.
  """
  def log(action, opts \\ []) do
    %__MODULE__{}
    |> changeset(%{
      action: action,
      resource_type: Keyword.get(opts, :resource_type),
      resource_id: Keyword.get(opts, :resource_id),
      metadata: Keyword.get(opts, :metadata, %{}),
      user_id: Keyword.get(opts, :user_id),
      ip_address: Keyword.get(opts, :ip_address)
    })
    |> Repo.insert()
  end

  @doc """
  Lists recent audit log entries.
  """
  def list_recent(limit \\ 50) do
    __MODULE__
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
