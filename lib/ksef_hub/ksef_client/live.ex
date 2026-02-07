defmodule KsefHub.KsefClient.Live do
  @moduledoc """
  Production HTTP implementation of the KSeF API client.
  Uses Req for HTTP requests against the KSeF REST API.
  """

  @behaviour KsefHub.KsefClient.Behaviour

  @spec base_url() :: String.t()
  defp base_url, do: Application.get_env(:ksef_hub, :ksef_api_url, "https://ksef-test.mf.gov.pl")

  @spec api_url(String.t()) :: String.t()
  defp api_url(path), do: "#{base_url()}/api/online#{path}"

  @impl true
  def get_challenge(nip) do
    url = api_url("/Session/AuthorisationChallenge")
    body = %{"contextIdentifier" => %{"type" => "onip", "identifier" => nip}}

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           challenge: body["challenge"],
           timestamp: body["timestamp"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def authenticate_xades(signed_xml) do
    url = api_url("/Session/AuthenticationToken/XadesSignature")

    case Req.post(url, body: signed_xml, headers: [{"content-type", "application/octet-stream"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           reference_number: body["referenceNumber"],
           operation_token: body["operationToken"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def poll_auth_status(reference_number) do
    url = api_url("/Session/Status/#{reference_number}")

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"processingCode" => 200}}} ->
        {:ok, :success}

      {:ok, %{status: 200, body: %{"processingCode" => _}}} ->
        {:ok, :pending}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def redeem_tokens(operation_token) do
    url = api_url("/Session/Token/Redeem")

    case Req.post(url, json: %{"operationToken" => operation_token}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["accessToken"],
           refresh_token: body["refreshToken"],
           access_valid_until: parse_datetime(body["accessTokenValidUntil"]),
           refresh_valid_until: parse_datetime(body["refreshTokenValidUntil"])
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def refresh_access_token(refresh_token) do
    url = api_url("/Session/Token/Refresh")

    case Req.post(url, json: %{"refreshToken" => refresh_token}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["accessToken"],
           valid_until: parse_datetime(body["accessTokenValidUntil"])
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:ksef_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def query_invoice_metadata(access_token, filters, opts \\ []) do
    url = api_url("/Query/Invoice/Sync")
    page_offset = Keyword.get(opts, :page_offset, 0)

    body = %{
      "queryCriteria" => build_query_criteria(filters),
      "pageOffset" => page_offset,
      "pageSize" => Keyword.get(opts, :page_size, 100)
    }

    headers = [{"SessionToken", access_token}]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           invoices: body["invoiceHeaderList"] || [],
           has_more: body["hasMore"] || false,
           is_truncated: body["isTruncated"] || false
         }}

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
  def download_invoice(access_token, ksef_number) do
    url = api_url("/Invoice/Get/#{ksef_number}")
    headers = [{"SessionToken", access_token}]

    case Req.get(url, headers: headers) do
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
    url = api_url("/Session/Terminate")
    headers = [{"SessionToken", token}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:ksef_error, status, body}}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  # --- Private ---

  @spec build_query_criteria(map()) :: map()
  defp build_query_criteria(filters) do
    []
    |> maybe_put(:type, filters[:type], fn type ->
      {"subjectType", if(type == "income", do: "subject1", else: "subject2")}
    end)
    |> maybe_put(:date_from, filters[:date_from], fn dt ->
      {"acquisitionTimestampThresholdFrom", DateTime.to_iso8601(dt)}
    end)
    |> maybe_put(:date_to, filters[:date_to], fn dt ->
      {"acquisitionTimestampThresholdTo", DateTime.to_iso8601(dt)}
    end)
    |> Map.new()
  end

  @spec maybe_put(list(), atom(), term(), (term() -> {String.t(), String.t()})) :: list()
  defp maybe_put(acc, _key, nil, _fun), do: acc
  defp maybe_put(acc, _key, value, fun), do: [fun.(value) | acc]

  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  @spec get_retry_after(Req.Response.t()) :: non_neg_integer()
  defp get_retry_after(%{headers: headers}) when is_map(headers) do
    case headers["retry-after"] do
      [value | _] -> String.to_integer(value)
      _ -> 5
    end
  rescue
    _ -> 5
  end
end
