defmodule KsefHub.Unstructured.ClientTest do
  use ExUnit.Case, async: false

  alias KsefHub.Unstructured.Client

  @moduletag capture_log: true

  describe "extract/2" do
    test "returns error when URL not configured" do
      assert {:error, :unstructured_service_not_configured} = Client.extract("pdf data", [])
    end

    test "returns error when token not configured" do
      Application.put_env(:ksef_hub, :unstructured_url, "http://localhost:9000")
      on_exit(fn -> Application.delete_env(:ksef_hub, :unstructured_url) end)

      assert {:error, :unstructured_token_not_configured} = Client.extract("pdf data", [])
    end

    test "returns error for non-binary input" do
      assert {:error, :invalid_pdf} = Client.extract(123, [])
    end

    test "returns extracted data on 200 success" do
      setup_unstructured_config()

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/extract"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-token"]

        Req.Test.json(conn, %{"seller_nip" => "1234567890"})
      end)

      assert {:ok, %{"seller_nip" => "1234567890"}} =
               Client.extract("pdf data", filename: "test.pdf")
    end

    test "returns error on non-200 status" do
      setup_unstructured_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "internal"}))
      end)

      assert {:error, {:unstructured_service_error, 500}} =
               Client.extract("pdf data", filename: "test.pdf")
    end

    test "returns error on network failure" do
      setup_unstructured_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.extract("pdf data", filename: "test.pdf")
    end
  end

  describe "health/0" do
    test "returns error when URL not configured" do
      assert {:error, :unstructured_service_not_configured} = Client.health()
    end

    test "returns health data on 200 success" do
      setup_unstructured_config()

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/health"

        Req.Test.json(conn, %{"status" => "ok"})
      end)

      assert {:ok, %{"status" => "ok"}} = Client.health()
    end

    test "returns error for non-map body" do
      setup_unstructured_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "OK")
      end)

      assert {:error, {:invalid_payload, "OK"}} = Client.health()
    end

    test "returns error on non-200 status" do
      setup_unstructured_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(503, Jason.encode!(%{"error" => "unavailable"}))
      end)

      assert {:error, {:unstructured_service_error, 503}} = Client.health()
    end
  end

  @spec setup_unstructured_config() :: :ok
  defp setup_unstructured_config do
    Application.put_env(:ksef_hub, :unstructured_url, "http://localhost:9000")
    Application.put_env(:ksef_hub, :unstructured_api_token, "test-token")

    on_exit(fn ->
      Application.delete_env(:ksef_hub, :unstructured_url)
      Application.delete_env(:ksef_hub, :unstructured_api_token)
    end)
  end
end
