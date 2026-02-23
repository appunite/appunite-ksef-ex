defmodule KsefHub.Predictions.StubService do
  @moduledoc false
  @behaviour KsefHub.Predictions.Behaviour

  @impl true
  def predict_category(_input) do
    {:ok,
     %{
       "predicted_label" => "unknown:category",
       "confidence" => 0.10,
       "model_version" => "stub",
       "probabilities" => %{}
     }}
  end

  @impl true
  def predict_tag(_input) do
    {:ok,
     %{
       "predicted_label" => "unknown-tag",
       "confidence" => 0.10,
       "model_version" => "stub",
       "probabilities" => %{}
     }}
  end

  @impl true
  def health do
    {:ok, %{"status" => "ok"}}
  end
end
