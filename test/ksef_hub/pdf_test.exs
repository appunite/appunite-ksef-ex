defmodule KsefHub.PdfTest do
  use ExUnit.Case, async: true

  describe "behaviour" do
    test "implements Pdf.Behaviour callbacks" do
      behaviours =
        KsefHub.Pdf.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert KsefHub.Pdf.Behaviour in behaviours
    end
  end
end
