defmodule KsefHub.InvoiceClassifier.StubClient do
  @moduledoc false
  @behaviour KsefHub.InvoiceClassifier.Behaviour

  @impl true
  def predict_category(_input) do
    {:ok,
     %{
       "top_category" => "unknown:category",
       "top_probability" => 0.10,
       "model_version" => "stub",
       "probabilities" => %{}
     }}
  end

  @impl true
  def predict_tag(_input) do
    {:ok,
     %{
       "top_tag" => "unknown-tag",
       "top_probability" => 0.10,
       "model_version" => "stub",
       "probabilities" => %{}
     }}
  end

  @impl true
  def health do
    {:ok, %{"status" => "ok"}}
  end
end
