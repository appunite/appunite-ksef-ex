defmodule KsefHub.Sync.Checkpoints do
  @moduledoc """
  Context functions for sync checkpoint management.
  Tracks the last-seen timestamp per sync type (income/expense) and NIP.
  """

  alias KsefHub.Repo
  alias KsefHub.Sync.Checkpoint

  @default_lookback_days 90

  @doc """
  Gets or initializes a checkpoint for the given type and NIP.
  If none exists, returns a checkpoint starting from `default_lookback_days` ago.
  """
  def get_or_init(checkpoint_type, nip) do
    case Repo.get_by(Checkpoint, checkpoint_type: checkpoint_type, nip: nip) do
      nil ->
        %Checkpoint{
          checkpoint_type: checkpoint_type,
          nip: nip,
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
  def advance(checkpoint_type, nip, new_timestamp) do
    %Checkpoint{}
    |> Checkpoint.changeset(%{
      checkpoint_type: checkpoint_type,
      nip: nip,
      last_seen_timestamp: new_timestamp,
      metadata: %{updated_reason: "sync_advance"}
    })
    |> Repo.insert(
      on_conflict: {:replace, [:last_seen_timestamp, :metadata, :updated_at]},
      conflict_target: [:checkpoint_type, :nip],
      returning: true
    )
  end
end
