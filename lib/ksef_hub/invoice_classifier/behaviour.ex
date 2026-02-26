defmodule KsefHub.InvoiceClassifier.Behaviour do
  @moduledoc """
  Behaviour for the ML classification service (au-payroll-model-categories sidecar).

  Defines callbacks for category and tag prediction on expense invoices.
  """

  @callback predict_category(input :: map()) :: {:ok, map()} | {:error, term()}
  @callback predict_tag(input :: map()) :: {:ok, map()} | {:error, term()}
  @callback health() :: {:ok, map()} | {:error, term()}
end
