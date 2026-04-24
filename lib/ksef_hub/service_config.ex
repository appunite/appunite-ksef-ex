defmodule KsefHub.ServiceConfig do
  @moduledoc """
  Context for per-company classifier service configuration.

  Each company has its own classifier config stored in the database.
  Classification is disabled by default and must be explicitly enabled
  with a URL, token, and confidence thresholds.
  """

  alias KsefHub.ActivityLog.TrackedRepo
  alias KsefHub.Credentials.Encryption
  alias KsefHub.Repo
  alias KsefHub.ServiceConfig.ClassifierConfig

  @doc "Returns the classifier config for a company, or nil if none exists."
  @spec get_classifier_config(Ecto.UUID.t()) :: ClassifierConfig.t() | nil
  def get_classifier_config(company_id) do
    Repo.get_by(ClassifierConfig, company_id: company_id)
  end

  @doc """
  Returns the classifier config for a company, creating a disabled default if none exists.
  """
  @spec get_or_create_classifier_config(Ecto.UUID.t()) :: ClassifierConfig.t()
  def get_or_create_classifier_config(company_id) do
    case get_classifier_config(company_id) do
      nil ->
        %ClassifierConfig{company_id: company_id}
        |> Ecto.Changeset.change()
        |> Repo.insert(on_conflict: :nothing, conflict_target: :company_id)
        |> case do
          {:ok, %{id: nil}} -> Repo.get_by!(ClassifierConfig, company_id: company_id)
          {:ok, config} -> config
        end

      config ->
        config
    end
  end

  @doc """
  Returns a changeset for a classifier config, suitable for form building and validation.
  """
  @spec change_classifier_config(ClassifierConfig.t(), map()) :: Ecto.Changeset.t()
  def change_classifier_config(%ClassifierConfig{} = config, attrs \\ %{}) do
    ClassifierConfig.changeset(config, attrs)
  end

  @doc """
  Updates a classifier config, encrypting the API token if provided.

  Actor metadata (`user_id`, `actor_label`) is passed via `opts` and forwarded
  to TrackedRepo for activity log emission. The `updated_by_id` field is derived
  from `opts[:user_id]` server-side.
  """
  @spec update_classifier_config(ClassifierConfig.t(), map(), keyword()) ::
          {:ok, ClassifierConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_classifier_config(%ClassifierConfig{} = config, attrs, opts \\ []) do
    changeset = ClassifierConfig.changeset(config, attrs)

    # Set updated_by_id from actor opts, not from form attrs
    changeset =
      case Keyword.get(opts, :user_id) do
        nil -> changeset
        user_id -> Ecto.Changeset.put_change(changeset, :updated_by_id, user_id)
      end

    # Handle API token: Ecto casts "" to nil, so check raw params for explicit blank
    changeset =
      case Map.get(attrs, "api_token") || Map.get(attrs, :api_token) do
        nil ->
          changeset

        "" ->
          Ecto.Changeset.put_change(changeset, :api_token_encrypted, nil)

        token when is_binary(token) ->
          {:ok, encrypted} = Encryption.encrypt(token)
          Ecto.Changeset.put_change(changeset, :api_token_encrypted, encrypted)
      end

    TrackedRepo.update(
      changeset,
      opts ++ [action: "classifier_config.updated"]
    )
  end
end
