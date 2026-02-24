defmodule KsefHub.Predictions.PredictionServiceTest do
  use ExUnit.Case, async: true

  alias KsefHub.Predictions.PredictionService

  @moduletag capture_log: true

  describe "predict_category/1" do
    test "returns error when URL not configured" do
      assert {:error, :prediction_service_not_configured} =
               PredictionService.predict_category(%{invoice_title: "Test"})
    end

    test "returns prediction on 200 success" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/predict/category"

        Req.Test.json(conn, %{"category" => "office", "confidence" => 0.95})
      end)

      assert {:ok, %{"category" => "office", "confidence" => 0.95}} =
               PredictionService.predict_category(%{invoice_title: "Office supplies"})
    end

    test "returns error on non-200 status" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "model failed"}))
      end)

      assert {:error, {:prediction_service_error, 500}} =
               PredictionService.predict_category(%{invoice_title: "Test"})
    end

    test "returns error on network failure" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :econnrefused}}} =
               PredictionService.predict_category(%{invoice_title: "Test"})
    end
  end

  describe "predict_tag/1" do
    test "returns error when URL not configured" do
      assert {:error, :prediction_service_not_configured} =
               PredictionService.predict_tag(%{invoice_title: "Test"})
    end

    test "returns prediction on 200 success" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/predict/tag"

        Req.Test.json(conn, %{"tag" => "recurring", "confidence" => 0.88})
      end)

      assert {:ok, %{"tag" => "recurring", "confidence" => 0.88}} =
               PredictionService.predict_tag(%{invoice_title: "Monthly subscription"})
    end

    test "returns error on non-200 status" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(422, Jason.encode!(%{"error" => "bad input"}))
      end)

      assert {:error, {:prediction_service_error, 422}} =
               PredictionService.predict_tag(%{invoice_title: "Test"})
    end
  end

  describe "health/0" do
    test "returns error when URL not configured" do
      assert {:error, :prediction_service_not_configured} = PredictionService.health()
    end

    test "returns health data on 200 success" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/health"

        Req.Test.json(conn, %{"status" => "healthy", "model_version" => "1.2.0"})
      end)

      assert {:ok, %{"status" => "healthy", "model_version" => "1.2.0"}} =
               PredictionService.health()
    end

    test "returns error for non-map body" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "OK")
      end)

      assert {:error, {:invalid_payload, "OK"}} = PredictionService.health()
    end

    test "returns error on non-200 status" do
      setup_prediction_config()

      Req.Test.stub(PredictionService, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(503, Jason.encode!(%{"error" => "unavailable"}))
      end)

      assert {:error, {:prediction_service_error, 503}} = PredictionService.health()
    end
  end

  defp setup_prediction_config do
    Application.put_env(:ksef_hub, :prediction_service_url, "http://localhost:8080")

    on_exit(fn ->
      Application.delete_env(:ksef_hub, :prediction_service_url)
    end)
  end
end
