defmodule KsefHub.Sync.Checkpoints do
  @moduledoc """
  Context functions for sync checkpoint management.
  Tracks the last-seen timestamp per sync type (income/expense) and company.
  """

  alias KsefHub.Repo
  alias KsefHub.Sync.Checkpoint

  @default_lookback_days 90

  @doc """
  Gets or initializes a checkpoint for the given type and company.
  If none exists, returns a checkpoint starting from `default_lookback_days` ago.
  """
  @spec get_or_init(atom(), Ecto.UUID.t()) :: Checkpoint.t()
  def get_or_init(checkpoint_type, company_id) do
    case Repo.get_by(Checkpoint, checkpoint_type: checkpoint_type, company_id: company_id) do
      nil ->
        %Checkpoint{
          checkpoint_type: checkpoint_type,
          company_id: company_id,
          last_seen_timestamp: DateTime.add(DateTime.utc_now(), -@default_lookback_days * 86_400),
          metadata: %{}
        }

      checkpoint ->
        checkpoint
    end
  end

  @doc """
  Advances the checkpoint to a new timestamp. Persists via upsert.
  """
  @spec advance(atom(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Checkpoint.t()} | {:error, Ecto.Changeset.t()}
  def advance(checkpoint_type, company_id, new_timestamp) do
    %Checkpoint{}
    |> Checkpoint.changeset(%{
      checkpoint_type: checkpoint_type,
      company_id: company_id,
      last_seen_timestamp: new_timestamp,
      metadata: %{updated_reason: "sync_advance"}
    })
    |> Repo.insert(
      on_conflict: {:replace, [:last_seen_timestamp, :metadata, :updated_at]},
      conflict_target: [:checkpoint_type, :company_id],
      returning: true
    )
  end
end
