defmodule KsefHub.Predictions.PredictionService do
  @moduledoc """
  HTTP client for the au-payroll-model-categories ML prediction sidecar.

  Calls `POST /predict/category` and `POST /predict/tag` endpoints to classify
  expense invoices. Returns predicted label with confidence scores.
  """

  @behaviour KsefHub.Predictions.Behaviour

  require Logger

  @receive_timeout 15_000

  @doc "Predicts a category for the given invoice input."
  @spec predict_category(map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def predict_category(input) when is_map(input) do
    post("/predict/category", input)
  end

  @doc "Predicts a tag for the given invoice input."
  @spec predict_tag(map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def predict_tag(input) when is_map(input) do
    post("/predict/tag", input)
  end

  @doc "Checks the health of the prediction service."
  @spec health() :: {:ok, map()} | {:error, term()}
  @impl true
  def health do
    with {:ok, base_url} <- fetch_url() do
      url = "#{base_url}/health"

      case Req.get(url, receive_timeout: @receive_timeout) do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          {:ok, body}

        {:ok, %{status: 200, body: body}} ->
          {:error, {:invalid_payload, body}}

        {:ok, %{status: status}} ->
          {:error, {:prediction_service_error, status}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @spec post(String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp post(path, input) do
    with {:ok, base_url} <- fetch_url() do
      do_request(base_url, path, input)
    end
  end

  @spec fetch_url() :: {:ok, String.t()} | {:error, :prediction_service_not_configured}
  defp fetch_url do
    case Application.get_env(:ksef_hub, :prediction_service_url) do
      nil -> {:error, :prediction_service_not_configured}
      url -> {:ok, url}
    end
  end

  @spec do_request(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp do_request(base_url, path, input) do
    url = "#{base_url}#{path}"

    case Req.post(url, json: input, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Prediction service returned #{status} for #{path}: #{inspect(body, limit: 200)}"
        )

        {:error, {:prediction_service_error, status}}

      {:error, reason} ->
        Logger.error("Prediction service request failed for #{path}: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end
end
