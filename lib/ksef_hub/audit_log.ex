defmodule KsefHub.AuditLog do
  @moduledoc "Audit log schema and helpers. Records security-relevant actions."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias KsefHub.Repo

  @type t :: %__MODULE__{}

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

  @doc "Builds a changeset for an audit log entry."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:action, :resource_type, :resource_id, :metadata, :user_id, :ip_address])
    |> validate_required([:action])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates an audit log entry.
  """
  @spec log(String.t(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
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
  @max_limit 1000

  @spec list_recent(non_neg_integer()) :: [t()]
  def list_recent(limit \\ 50)

  def list_recent(limit) when is_integer(limit) and limit > 0 do
    clamped = min(limit, @max_limit)

    __MODULE__
    |> order_by([a], desc: a.inserted_at)
    |> limit(^clamped)
    |> Repo.all()
  end

  def list_recent(_), do: list_recent(50)
end
