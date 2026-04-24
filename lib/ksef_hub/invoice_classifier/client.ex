defmodule KsefHub.InvoiceClassifier.Client do
  @moduledoc """
  HTTP client for the ML classification service.

  Calls `POST /predict/category` and `POST /predict/tag` endpoints to classify
  invoices. Returns predicted label with confidence scores.

  URL and API token are provided per-call via the `config` map,
  resolved from the company's `ClassifierConfig` in the database.
  """

  @behaviour KsefHub.InvoiceClassifier.Behaviour

  require Logger

  @receive_timeout 15_000

  @doc "Predicts a category for the given invoice input."
  @spec predict_category(map(), map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def predict_category(input, config) when is_map(input) do
    with {:ok, body} <- post("/predict/category", input, config) do
      normalize_response(body, "top_category")
    end
  end

  @doc "Predicts a tag for the given invoice input."
  @spec predict_tag(map(), map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def predict_tag(input, config) when is_map(input) do
    with {:ok, body} <- post("/predict/tag", input, config) do
      normalize_response(body, "top_tag")
    end
  end

  @doc "Checks the health of the classification service."
  @spec health(map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def health(config) do
    case fetch_url(config) do
      {:ok, base_url} ->
        case base_url |> build_req(config) |> Req.get(url: "/health") do
          {:ok, %{status: 200, body: body}} when is_map(body) ->
            {:ok, body}

          {:ok, %{status: 200, body: body}} ->
            {:error, {:invalid_payload, body}}

          {:ok, %{status: status}} ->
            {:error, {:classifier_error, status}}

          {:error, reason} ->
            {:error, {:request_failed, reason}}
        end

      error ->
        error
    end
  end

  @spec post(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  defp post(path, input, config) do
    case fetch_url(config) do
      {:ok, base_url} -> do_request(base_url, path, input, config)
      error -> error
    end
  end

  @spec fetch_url(map()) :: {:ok, String.t()} | {:error, :classifier_not_configured}
  defp fetch_url(config) do
    case config do
      %{url: url} when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, :classifier_not_configured}
    end
  end

  @spec do_request(String.t(), String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  defp do_request(base_url, path, input, config) do
    case base_url |> build_req(config) |> Req.post(url: path, json: input) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "Classification service returned #{status} for #{path}: #{inspect(body, limit: 200)}"
        )

        {:error, {:classifier_error, status}}

      {:error, reason} ->
        Logger.error("Classification service request failed for #{path}: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @spec build_req(String.t(), map()) :: Req.Request.t()
  defp build_req(base_url, config) do
    req_options = Application.get_env(:ksef_hub, :invoice_classifier_req_options, [])
    {extra_headers, req_options} = Keyword.pop(req_options, :headers, [])

    auth_headers =
      case config[:api_token] do
        token when is_binary(token) and token != "" ->
          [{"authorization", "Bearer #{token}"}]

        _ ->
          []
      end

    [
      base_url: base_url,
      receive_timeout: @receive_timeout,
      headers: auth_headers ++ extra_headers
    ]
    |> Keyword.merge(req_options)
    |> Req.new()
  end

  @spec normalize_response(map(), String.t()) :: {:ok, map()} | {:error, :invalid_response}
  defp normalize_response(body, label_key) do
    with {:ok, label} <- fetch_string(body, label_key),
         {:ok, probability} <- fetch_number(body, "top_probability") do
      {:ok,
       %{
         "predicted_label" => label,
         "confidence" => probability,
         "model_version" => body["model_version"],
         "probabilities" => body["probabilities"]
       }}
    else
      :error ->
        Logger.error(
          "Classifier response missing required keys (#{label_key}, top_probability): #{inspect(body, limit: 200)}"
        )

        {:error, :invalid_response}
    end
  end

  @spec fetch_string(map(), String.t()) :: {:ok, String.t()} | :error
  defp fetch_string(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
  end

  @spec fetch_number(map(), String.t()) :: {:ok, number()} | :error
  defp fetch_number(map, key) do
    case map[key] do
      value when is_number(value) -> {:ok, value}
      _ -> :error
    end
  end
end
