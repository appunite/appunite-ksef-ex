defmodule KsefHub.InvoiceClassifier.ClientTest do
  use ExUnit.Case, async: false

  alias KsefHub.InvoiceClassifier.Client

  @moduletag capture_log: true

  # DB seeds load URLs into Application env on boot — clear them for isolation
  setup do
    url = Application.get_env(:ksef_hub, :invoice_classifier_url)
    token = Application.get_env(:ksef_hub, :invoice_classifier_api_token)
    Application.delete_env(:ksef_hub, :invoice_classifier_url)
    Application.delete_env(:ksef_hub, :invoice_classifier_api_token)

    on_exit(fn ->
      if url, do: Application.put_env(:ksef_hub, :invoice_classifier_url, url)
      if token, do: Application.put_env(:ksef_hub, :invoice_classifier_api_token, token)
    end)

    :ok
  end

  describe "predict_category/1" do
    test "returns error when URL not configured" do
      assert {:error, :classifier_not_configured} =
               Client.predict_category(%{invoice_title: "Test"})
    end

    test "normalizes sidecar response to canonical keys" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/predict/category"

        Req.Test.json(conn, %{
          "top_category" => "operations:infrastructure",
          "top_probability" => 0.95,
          "model_version" => "1.0.0",
          "probabilities" => %{"operations:infrastructure" => 0.95, "other" => 0.05}
        })
      end)

      assert {:ok, result} = Client.predict_category(%{invoice_title: "Office supplies"})
      assert result["predicted_label"] == "operations:infrastructure"
      assert result["confidence"] == 0.95
      assert result["model_version"] == "1.0.0"
      assert result["probabilities"]["operations:infrastructure"] == 0.95
    end

    test "returns error when response missing required keys" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "format"})
      end)

      assert {:error, :invalid_response} =
               Client.predict_category(%{invoice_title: "Test"})
    end

    test "returns error on non-200 status" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "model failed"}))
      end)

      assert {:error, {:classifier_error, 500}} =
               Client.predict_category(%{invoice_title: "Test"})
    end

    test "returns error on network failure" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.predict_category(%{invoice_title: "Test"})
    end
  end

  describe "predict_tag/1" do
    test "returns error when URL not configured" do
      assert {:error, :classifier_not_configured} =
               Client.predict_tag(%{invoice_title: "Test"})
    end

    test "normalizes sidecar response to canonical keys" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/predict/tag"

        Req.Test.json(conn, %{
          "top_tag" => "benefit-books-formula",
          "top_probability" => 0.88,
          "model_version" => "1.0.0",
          "probabilities" => %{"benefit-books-formula" => 0.88, "other" => 0.12}
        })
      end)

      assert {:ok, result} = Client.predict_tag(%{invoice_title: "Monthly subscription"})
      assert result["predicted_label"] == "benefit-books-formula"
      assert result["confidence"] == 0.88
      assert result["model_version"] == "1.0.0"
    end

    test "returns error when response missing required keys" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "format"})
      end)

      assert {:error, :invalid_response} =
               Client.predict_tag(%{invoice_title: "Test"})
    end

    test "returns error on non-200 status" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(422, Jason.encode!(%{"error" => "bad input"}))
      end)

      assert {:error, {:classifier_error, 422}} =
               Client.predict_tag(%{invoice_title: "Test"})
    end

    test "returns error on network failure" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.predict_tag(%{invoice_title: "Test"})
    end
  end

  describe "health/0" do
    test "returns error when URL not configured" do
      assert {:error, :classifier_not_configured} = Client.health()
    end

    test "returns health data on 200 success" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/health"

        Req.Test.json(conn, %{"status" => "healthy", "model_version" => "1.2.0"})
      end)

      assert {:ok, %{"status" => "healthy", "model_version" => "1.2.0"}} =
               Client.health()
    end

    test "returns error for non-map body" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "OK")
      end)

      assert {:error, {:invalid_payload, "OK"}} = Client.health()
    end

    test "returns error on non-200 status" do
      setup_classifier_config()

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(503, Jason.encode!(%{"error" => "unavailable"}))
      end)

      assert {:error, {:classifier_error, 503}} = Client.health()
    end
  end

  @spec setup_classifier_config() :: :ok
  defp setup_classifier_config do
    Application.put_env(:ksef_hub, :invoice_classifier_url, "http://localhost:8080")

    on_exit(fn ->
      Application.delete_env(:ksef_hub, :invoice_classifier_url)
    end)
  end
end
