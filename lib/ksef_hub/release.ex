defmodule KsefHub.Release do
  @moduledoc """
  Release tasks for running migrations in production.

  Mix is not available in production releases, so these functions
  provide the same functionality via `bin/ksef_hub eval`.

  ## Examples

      bin/ksef_hub eval "KsefHub.Release.migrate()"
      bin/ksef_hub eval "KsefHub.Release.rollback(KsefHub.Repo, 20240101000000)"
  """

  @app :ksef_hub

  @doc """
  Runs all pending Ecto migrations.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Rolls back migrations to the given `version`.
  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @spec load_app() :: :ok | {:error, term()}
  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end

  @spec repos() :: [module()]
  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
