defmodule KsefHub.KsefClient.Live do
  @moduledoc """
  Production HTTP implementation of the KSeF v2 API client.
  Uses Req for HTTP requests against the KSeF REST API.
  """

  @behaviour KsefHub.KsefClient.Behaviour

  @receive_timeout :timer.seconds(30)
  @retry_count 2
  @retry_delay :timer.seconds(1)

  # Proactive rate limit delays per KSeF guidelines
  @query_delay_ms 500
  @download_delay_ms 125

  defp base_url,
    do: Application.get_env(:ksef_hub, :ksef_api_url, "https://api-test.ksef.mf.gov.pl")

  defp api_url(path), do: "#{base_url()}/v2#{path}"

  defp bearer_headers(token), do: [{"authorization", "Bearer #{token}"}]

  @spec req_options() :: keyword()
  defp req_options do
    [
      receive_timeout: @receive_timeout,
      retry: :transient,
      max_retries: @retry_count,
      retry_delay: @retry_delay
    ]
  end

  @spec req_options_no_retry() :: keyword()
  defp req_options_no_retry do
    [
      receive_timeout: @receive_timeout,
      retry: false
    ]
  end

  @impl true
  def get_challenge do
    url = api_url("/auth/challenge")

    case Req.post(url, [json: %{}] ++ req_options_no_retry()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           challenge: body["challenge"],
           timestamp: body["timestamp"]
         }}

      {:ok, %{status: status, body: body}} when is_binary(body) ->
        {:error, {:unexpected_html_response, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def authenticate_xades(signed_xml) do
    url = api_url("/auth/xades-signature")

    case Req.post(
           url,
           [body: signed_xml, headers: [{"content-type", "application/xml"}]] ++
             req_options_no_retry()
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 202] and is_map(body) ->
        auth_token_data = body["authenticationToken"] || %{}

        {:ok,
         %{
           reference_number: body["referenceNumber"],
           auth_token: auth_token_data["token"],
           auth_token_valid_until: parse_datetime(auth_token_data["validUntil"])
         }}

      {:ok, %{status: status, body: body}} when is_binary(body) ->
        {:error, {:unexpected_html_response, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def poll_auth_status(reference_number, auth_token) do
    url = api_url("/auth/#{reference_number}")
    headers = bearer_headers(auth_token)

    case Req.get(url, [headers: headers] ++ req_options()) do
      {:ok, %{status: 200, body: %{"status" => %{"code" => code}}}}
      when code >= 200 and code < 300 ->
        {:ok, :success}

      {:ok, %{status: 200, body: %{"status" => %{"code" => code}}}} when code < 200 ->
        {:ok, :pending}

      {:ok, %{status: 200, body: %{"status" => %{"code" => code}} = body}} when code >= 400 ->
        {:error, {:ksef_error, code, body}}

      {:ok, %{status: status, body: body}} when is_binary(body) ->
        {:error, {:unexpected_html_response, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def redeem_tokens(auth_token) do
    url = api_url("/auth/token/redeem")
    headers = bearer_headers(auth_token)

    case Req.post(url, [json: %{}, headers: headers] ++ req_options_no_retry()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        access = body["accessToken"] || %{}
        refresh = body["refreshToken"] || %{}

        {:ok,
         %{
           access_token: access["token"],
           refresh_token: refresh["token"],
           access_valid_until: parse_datetime(access["validUntil"]),
           refresh_valid_until: parse_datetime(refresh["validUntil"])
         }}

      {:ok, %{status: status, body: body}} when is_binary(body) ->
        {:error, {:unexpected_html_response, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def refresh_access_token(refresh_token) do
    url = api_url("/auth/token/refresh")
    headers = bearer_headers(refresh_token)

    case Req.post(url, [json: %{}, headers: headers] ++ req_options_no_retry()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        access = body["accessToken"] || %{}

        {:ok,
         %{
           access_token: access["token"],
           valid_until: parse_datetime(access["validUntil"])
         }}

      {:ok, %{status: status, body: body}} when is_binary(body) ->
        {:error, {:unexpected_html_response, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def query_invoice_metadata(access_token, filters, opts \\ []) do
    Process.sleep(@query_delay_ms)

    page_offset = Keyword.get(opts, :page_offset, 0)
    page_size = Keyword.get(opts, :page_size, 100)

    params = [
      {"pageOffset", page_offset},
      {"pageSize", page_size},
      {"sortOrder", "Asc"}
    ]

    url = api_url("/invoices/query/metadata")
    headers = bearer_headers(access_token)
    body = build_query_filters(filters)

    case Req.post(url, [json: body, headers: headers, params: params] ++ req_options()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           invoices: body["invoices"] || [],
           has_more: body["hasMore"] || false,
           is_truncated: body["isTruncated"] || false
         }}

      {:ok, %{status: 429} = resp} ->
        retry_after = get_retry_after(resp)
        {:error, {:rate_limited, retry_after}}

      {:ok, %{status: status, body: body}} when is_binary(body) ->
        {:error, {:unexpected_html_response, status}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def download_invoice(access_token, ksef_number) do
    Process.sleep(@download_delay_ms)

    url = api_url("/invoices/ksef/#{ksef_number}")
    headers = bearer_headers(access_token)

    case Req.get(url, [headers: headers] ++ req_options()) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: 429} = resp} ->
        retry_after = get_retry_after(resp)
        {:error, {:rate_limited, retry_after}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def terminate_session(token) do
    url = api_url("/auth/sessions/current")
    headers = bearer_headers(token)

    case Req.delete(url, [headers: headers] ++ req_options_no_retry()) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:ksef_error, status, body}}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  # --- Private ---

  @spec build_query_filters(map()) :: map()
  defp build_query_filters(filters) do
    query = %{}

    query =
      case filters[:type] do
        :income -> Map.put(query, "subjectType", "Subject1")
        :expense -> Map.put(query, "subjectType", "Subject2")
        nil -> query
      end

    date_range = build_date_range(filters[:date_from], filters[:date_to])

    if date_range do
      Map.put(query, "dateRange", date_range)
    else
      query
    end
  end

  @spec build_date_range(DateTime.t() | nil, DateTime.t() | nil) :: map() | nil
  defp build_date_range(nil, nil), do: nil

  defp build_date_range(from, to) do
    range = %{"dateType" => "PermanentStorage"}
    range = if from, do: Map.put(range, "from", DateTime.to_iso8601(from)), else: range
    range = if to, do: Map.put(range, "to", DateTime.to_iso8601(to)), else: range
    range
  end

  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  @spec get_retry_after(map()) :: non_neg_integer()
  defp get_retry_after(%{headers: headers}) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> String.to_integer(value)
      nil -> 5
    end
  rescue
    _ -> 5
  end
end
