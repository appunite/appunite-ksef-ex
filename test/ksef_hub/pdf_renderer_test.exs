defmodule KsefHub.PdfRendererTest do
  use ExUnit.Case, async: true

  describe "behaviour" do
    test "implements PdfRenderer.Behaviour callbacks" do
      behaviours =
        KsefHub.PdfRenderer.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert KsefHub.PdfRenderer.Behaviour in behaviours
    end
  end
end
