defmodule KsefHub.Unstructured.ClientTest do
  use ExUnit.Case, async: true

  alias KsefHub.Unstructured.Client

  describe "extract/2" do
    test "returns error when URL not configured" do
      assert {:error, :unstructured_service_not_configured} = Client.extract("pdf data")
    end
  end

  describe "health/0" do
    test "returns error when URL not configured" do
      assert {:error, :unstructured_service_not_configured} = Client.health()
    end
  end
end
