defmodule KsefHub.InvoiceClassifier.ClientTest do
  use ExUnit.Case, async: true

  alias KsefHub.InvoiceClassifier.Client

  @moduletag capture_log: true

  @test_config %{url: "http://localhost:8080", api_token: nil}

  describe "predict_category/2" do
    test "returns error when URL not configured" do
      assert {:error, :classifier_not_configured} =
               Client.predict_category(%{invoice_title: "Test"}, %{url: nil, api_token: nil})
    end

    test "normalizes sidecar response to canonical keys" do
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

      assert {:ok, result} =
               Client.predict_category(%{invoice_title: "Office supplies"}, @test_config)

      assert result["predicted_label"] == "operations:infrastructure"
      assert result["confidence"] == 0.95
      assert result["model_version"] == "1.0.0"
      assert result["probabilities"]["operations:infrastructure"] == 0.95
    end

    test "returns error when response missing required keys" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "format"})
      end)

      assert {:error, :invalid_response} =
               Client.predict_category(%{invoice_title: "Test"}, @test_config)
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "model failed"}))
      end)

      assert {:error, {:classifier_error, 500}} =
               Client.predict_category(%{invoice_title: "Test"}, @test_config)
    end

    test "returns error on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.predict_category(%{invoice_title: "Test"}, @test_config)
    end
  end

  describe "predict_tag/2" do
    test "returns error when URL not configured" do
      assert {:error, :classifier_not_configured} =
               Client.predict_tag(%{invoice_title: "Test"}, %{url: nil, api_token: nil})
    end

    test "normalizes sidecar response to canonical keys" do
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

      assert {:ok, result} =
               Client.predict_tag(%{invoice_title: "Monthly subscription"}, @test_config)

      assert result["predicted_label"] == "benefit-books-formula"
      assert result["confidence"] == 0.88
      assert result["model_version"] == "1.0.0"
    end

    test "returns error when response missing required keys" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "format"})
      end)

      assert {:error, :invalid_response} =
               Client.predict_tag(%{invoice_title: "Test"}, @test_config)
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(422, Jason.encode!(%{"error" => "bad input"}))
      end)

      assert {:error, {:classifier_error, 422}} =
               Client.predict_tag(%{invoice_title: "Test"}, @test_config)
    end

    test "returns error on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               Client.predict_tag(%{invoice_title: "Test"}, @test_config)
    end
  end

  describe "health/1" do
    test "returns error when URL not configured" do
      assert {:error, :classifier_not_configured} = Client.health(%{url: nil, api_token: nil})
    end

    test "returns health data on 200 success" do
      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/health"

        Req.Test.json(conn, %{"status" => "healthy", "model_version" => "1.2.0"})
      end)

      assert {:ok, %{"status" => "healthy", "model_version" => "1.2.0"}} =
               Client.health(@test_config)
    end

    test "returns error for non-map body" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "OK")
      end)

      assert {:error, {:invalid_payload, "OK"}} = Client.health(@test_config)
    end

    test "returns error on non-200 status" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(503, Jason.encode!(%{"error" => "unavailable"}))
      end)

      assert {:error, {:classifier_error, 503}} = Client.health(@test_config)
    end
  end
end
