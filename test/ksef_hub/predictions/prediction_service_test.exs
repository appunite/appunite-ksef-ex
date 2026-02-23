defmodule KsefHub.Predictions.PredictionServiceTest do
  use ExUnit.Case, async: true

  alias KsefHub.Predictions.PredictionService

  describe "predict_category/1" do
    test "returns error when URL not configured" do
      assert {:error, :prediction_service_not_configured} =
               PredictionService.predict_category(%{invoice_title: "Test"})
    end
  end

  describe "predict_tag/1" do
    test "returns error when URL not configured" do
      assert {:error, :prediction_service_not_configured} =
               PredictionService.predict_tag(%{invoice_title: "Test"})
    end
  end

  describe "health/0" do
    test "returns error when URL not configured" do
      assert {:error, :prediction_service_not_configured} = PredictionService.health()
    end
  end
end
