defmodule KsefHub.InvoiceClassifier.Behaviour do
  @moduledoc """
  Behaviour for the ML classification service.

  Defines callbacks for category and tag prediction on invoices.
  All callbacks receive a config map with `:url` and optional `:api_token`
  for the target classification service.
  """

  @type config :: %{url: String.t(), api_token: String.t() | nil}

  @callback predict_category(input :: map(), config :: config()) ::
              {:ok, map()} | {:error, term()}
  @callback predict_tag(input :: map(), config :: config()) ::
              {:ok, map()} | {:error, term()}
  @callback health(config :: config()) :: {:ok, map()} | {:error, term()}
end
