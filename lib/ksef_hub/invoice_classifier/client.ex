defmodule KsefHub.InvoiceClassifier.Client do
  @moduledoc """
  HTTP client for the au-payroll-model-categories ML classification sidecar.

  Calls `POST /predict/category` and `POST /predict/tag` endpoints to classify
  expense invoices. Returns predicted label with confidence scores.
  """

  @behaviour KsefHub.InvoiceClassifier.Behaviour

  require Logger

  @receive_timeout 15_000

  @doc "Predicts a category for the given invoice input."
  @spec predict_category(map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def predict_category(input) when is_map(input) do
    with {:ok, body} <- post("/predict/category", input) do
      normalize_response(body, "top_category")
    end
  end

  @doc "Predicts a tag for the given invoice input."
  @spec predict_tag(map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def predict_tag(input) when is_map(input) do
    with {:ok, body} <- post("/predict/tag", input) do
      normalize_response(body, "top_tag")
    end
  end

  @doc "Checks the health of the classification service."
  @spec health() :: {:ok, map()} | {:error, term()}
  @impl true
  def health do
    with {:ok, base_url} <- fetch_url() do
      case base_url |> build_req() |> Req.get(url: "/health") do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          {:ok, body}

        {:ok, %{status: 200, body: body}} ->
          {:error, {:invalid_payload, body}}

        {:ok, %{status: status}} ->
          {:error, {:classifier_error, status}}

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

  @spec fetch_url() :: {:ok, String.t()} | {:error, :classifier_not_configured}
  defp fetch_url do
    case Application.get_env(:ksef_hub, :invoice_classifier_url) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, :classifier_not_configured}
    end
  end

  @spec do_request(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp do_request(base_url, path, input) do
    case base_url |> build_req() |> Req.post(url: path, json: input) do
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

  @spec build_req(String.t()) :: Req.Request.t()
  defp build_req(base_url) do
    req_options = Application.get_env(:ksef_hub, :invoice_classifier_req_options, [])
    {extra_headers, req_options} = Keyword.pop(req_options, :headers, [])

    auth_headers =
      case Application.get_env(:ksef_hub, :invoice_classifier_api_token) do
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

  # Normalizes sidecar-specific response keys to canonical keys used by the
  # classifier context. The `label_key` is the sidecar's top-prediction key
  # (e.g. "top_category" or "top_tag").
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
