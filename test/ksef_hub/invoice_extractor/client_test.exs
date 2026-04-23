defmodule KsefHub.InvoiceExtractor.ClientTest do
  use ExUnit.Case, async: false

  alias KsefHub.InvoiceExtractor.Client

  @moduletag capture_log: true

  # DB seeds load URLs into Application env on boot — clear them for isolation
  setup do
    url = Application.get_env(:ksef_hub, :invoice_extractor_url)
    token = Application.get_env(:ksef_hub, :invoice_extractor_api_token)
    Application.delete_env(:ksef_hub, :invoice_extractor_url)
    Application.delete_env(:ksef_hub, :invoice_extractor_api_token)

    on_exit(fn ->
      if url, do: Application.put_env(:ksef_hub, :invoice_extractor_url, url)
      if token, do: Application.put_env(:ksef_hub, :invoice_extractor_api_token, token)
    end)

    :ok
  end

  describe "extract/2" do
    test "returns error when URL not configured" do
      assert {:error, :extractor_not_configured} = Client.extract("pdf data", [])
    end

    test "returns error when token not configured" do
      Application.put_env(:ksef_hub, :invoice_extractor_url, "http://localhost:9000")
      Application.delete_env(:ksef_hub, :invoice_extractor_api_token)

      on_exit(fn -> Application.delete_env(:ksef_hub, :invoice_extractor_url) end)

      assert {:error, :extractor_token_not_configured} = Client.extract("pdf data", [])
    end

    test "returns error for non-binary input" do
      assert {:error, :invalid_pdf} = Client.extract(123, [])
    end

    test "returns extracted data on 200 success" do
      setup_extractor_config()

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
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "internal"}))
      end)

      assert {:error, {:extractor_error, 500}} =
               Client.extract("pdf data", filename: "test.pdf")
    end

    test "returns error on network failure" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.extract("pdf data", filename: "test.pdf")
    end

    test "retries on econnrefused and succeeds when service becomes available" do
      setup_extractor_config()

      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(Client, fn conn ->
        attempt = Agent.get_and_update(attempts, fn n -> {n, n + 1} end)

        if attempt == 0 do
          Req.Test.transport_error(conn, :econnrefused)
        else
          Req.Test.json(conn, %{"seller_nip" => "1234567890"})
        end
      end)

      assert {:ok, %{"seller_nip" => "1234567890"}} =
               Client.extract("pdf data", filename: "test.pdf")

      assert Agent.get(attempts, & &1) == 2
    end

    test "sends context as form field when provided in opts" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "context"
        assert body =~ "The company is Test Corp"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"seller_nip" => "1234567890"}))
      end)

      assert {:ok, _} =
               Client.extract("pdf data",
                 filename: "test.pdf",
                 context: "The company is Test Corp, NIP 1234567890."
               )
    end

    test "does not send context field when not provided" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        refute body =~ "context"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"seller_nip" => "1234567890"}))
      end)

      assert {:ok, _} = Client.extract("pdf data", filename: "test.pdf")
    end
  end

  describe "health/0" do
    test "returns error when URL not configured" do
      assert {:error, :extractor_not_configured} = Client.health()
    end

    test "returns health data on 200 success" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/health"

        Req.Test.json(conn, %{"status" => "ok"})
      end)

      assert {:ok, %{"status" => "ok"}} = Client.health()
    end

    test "returns error for non-map body" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "OK")
      end)

      assert {:error, {:invalid_payload, "OK"}} = Client.health()
    end

    test "returns error on non-200 status" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(503, Jason.encode!(%{"error" => "unavailable"}))
      end)

      assert {:error, {:extractor_error, 503}} = Client.health()
    end

    test "returns error on network failure" do
      setup_extractor_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.health()
    end
  end

  @spec setup_extractor_config() :: :ok
  defp setup_extractor_config do
    Application.put_env(:ksef_hub, :invoice_extractor_url, "http://localhost:9000")
    Application.put_env(:ksef_hub, :invoice_extractor_api_token, "test-token")

    on_exit(fn ->
      Application.delete_env(:ksef_hub, :invoice_extractor_url)
      Application.delete_env(:ksef_hub, :invoice_extractor_api_token)
    end)
  end
end
