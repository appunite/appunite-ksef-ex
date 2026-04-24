defmodule KsefHubWeb.HealthControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import Mox

  setup :verify_on_exit!

  describe "GET /healthz" do
    test "returns 200 with status ok", %{conn: conn} do
      conn = get(conn, ~p"/healthz")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  describe "GET /healthz/services" do
    test "returns 200 when all services are healthy", %{conn: conn} do
      KsefHub.PdfRenderer.Mock |> expect(:health, fn -> {:ok, %{"status" => "ok"}} end)
      KsefHub.InvoiceExtractor.Mock |> expect(:health, fn -> {:ok, %{"status" => "ok"}} end)

      conn = get(conn, ~p"/healthz/services")

      assert json_response(conn, 200) == %{
               "pdf_renderer" => "ok",
               "invoice_extractor" => "ok"
             }
    end

    test "returns 503 when a service is unhealthy", %{conn: conn} do
      KsefHub.PdfRenderer.Mock |> expect(:health, fn -> {:ok, %{"status" => "ok"}} end)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:health, fn -> {:error, {:extractor_error, 500}} end)

      conn = get(conn, ~p"/healthz/services")

      assert json_response(conn, 503) == %{
               "pdf_renderer" => "ok",
               "invoice_extractor" => "unhealthy"
             }
    end

    test "returns 503 when a service is not configured", %{conn: conn} do
      KsefHub.PdfRenderer.Mock
      |> expect(:health, fn -> {:error, :pdf_renderer_not_configured} end)

      KsefHub.InvoiceExtractor.Mock
      |> expect(:health, fn -> {:error, :extractor_not_configured} end)

      conn = get(conn, ~p"/healthz/services")

      assert json_response(conn, 503) == %{
               "pdf_renderer" => "unhealthy",
               "invoice_extractor" => "unhealthy"
             }
    end
  end
end
