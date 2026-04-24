defmodule KsefHub.InvoiceClassifier.StubClient do
  @moduledoc false
  @behaviour KsefHub.InvoiceClassifier.Behaviour

  @impl true
  def predict_category(_input, _config) do
    {:ok,
     %{
       "predicted_label" => "unknown:category",
       "confidence" => 0.10,
       "model_version" => "stub",
       "probabilities" => %{}
     }}
  end

  @impl true
  def predict_tag(_input, _config) do
    {:ok,
     %{
       "predicted_label" => "unknown-tag",
       "confidence" => 0.10,
       "model_version" => "stub",
       "probabilities" => %{}
     }}
  end

  @impl true
  def health(_config) do
    {:ok, %{"status" => "ok"}}
  end
end
