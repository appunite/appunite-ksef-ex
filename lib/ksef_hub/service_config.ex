defmodule KsefHub.ServiceConfig do
  @moduledoc """
  Context for per-company sidecar service configuration.

  Currently supports the invoice classifier only (the main per-company use case).
  PDF renderer and invoice extractor use global env vars exclusively.

  When a company's classifier config is **enabled**, its values override
  the global env-var defaults for that company's operations.
  """

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
  Updates a classifier config, encrypting the API token if provided.
  """
  @spec update_classifier_config(ClassifierConfig.t(), map()) ::
          {:ok, ClassifierConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_classifier_config(%ClassifierConfig{} = config, attrs) do
    changeset = ClassifierConfig.changeset(config, attrs)

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

    Repo.update(changeset)
  end

  @doc """
  Returns the current env-var defaults for display in the UI.
  """
  @spec env_defaults() :: map()
  def env_defaults do
    %{
      url: Application.get_env(:ksef_hub, :invoice_classifier_url),
      api_token_configured: Application.get_env(:ksef_hub, :invoice_classifier_api_token) != nil,
      category_confidence_threshold:
        Application.get_env(:ksef_hub, :category_confidence_threshold, 0.71),
      tag_confidence_threshold: Application.get_env(:ksef_hub, :tag_confidence_threshold, 0.95)
    }
  end
end
