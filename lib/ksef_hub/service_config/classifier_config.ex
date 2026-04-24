defmodule KsefHub.ServiceConfig.ClassifierConfig do
  @moduledoc """
  Per-company configuration for the invoice classifier service.

  When `enabled` is true, invoice classification runs using the configured
  URL, token, and thresholds. When `enabled` is false (default), no
  classification is performed for the company.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias KsefHub.Companies.Company

  @default_category_threshold 0.71
  @default_tag_threshold 0.95
  @default_url "http://localhost:3003"

  @doc "Returns the default category confidence threshold."
  @spec default_category_threshold() :: float()
  def default_category_threshold, do: @default_category_threshold

  @doc "Returns the default tag confidence threshold."
  @spec default_tag_threshold() :: float()
  def default_tag_threshold, do: @default_tag_threshold

  @doc "Returns the default classifier service URL."
  @spec default_url() :: String.t()
  def default_url, do: @default_url

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          company_id: Ecto.UUID.t() | nil,
          enabled: boolean(),
          url: String.t() | nil,
          api_token_encrypted: binary() | nil,
          category_confidence_threshold: float() | nil,
          tag_confidence_threshold: float() | nil,
          updated_by_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "classifier_configs" do
    belongs_to :company, Company
    field :enabled, :boolean, default: false
    field :url, :string
    field :api_token_encrypted, :binary
    field :category_confidence_threshold, :float
    field :tag_confidence_threshold, :float
    field :updated_by_id, :binary_id

    # Virtual field for accepting plaintext token in forms
    field :api_token, :string, virtual: true

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a classifier config."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :enabled,
      :url,
      :api_token,
      :category_confidence_threshold,
      :tag_confidence_threshold
    ])
    |> validate_when_enabled()
  end

  @spec validate_when_enabled(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_when_enabled(changeset) do
    if get_field(changeset, :enabled) do
      changeset
      |> validate_required([:url, :category_confidence_threshold, :tag_confidence_threshold])
      |> validate_url()
      |> validate_number(:category_confidence_threshold,
        greater_than: 0.0,
        less_than: 1.0,
        message: "must be between 0 and 1"
      )
      |> validate_number(:tag_confidence_threshold,
        greater_than: 0.0,
        less_than: 1.0,
        message: "must be between 0 and 1"
      )
    else
      changeset
    end
  end

  @spec validate_url(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [url: "must be a valid HTTP(S) URL"]
      end
    end)
  end
end
