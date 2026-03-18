defmodule KsefHub.EmojiGeneratorTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "generate_emoji/1" do
    test "delegates to configured client and returns emoji" do
      KsefHub.EmojiGenerator.Mock
      |> expect(:generate_emoji, fn context ->
        assert context.identifier == "finance:invoices"
        assert context.description == "Invoice processing"
        {:ok, "💰"}
      end)

      assert {:ok, "💰"} =
               KsefHub.EmojiGenerator.generate_emoji(%{
                 identifier: "finance:invoices",
                 description: "Invoice processing"
               })
    end

    test "returns error from client" do
      KsefHub.EmojiGenerator.Mock
      |> expect(:generate_emoji, fn _context ->
        {:error, :missing_api_key}
      end)

      assert {:error, :missing_api_key} =
               KsefHub.EmojiGenerator.generate_emoji(%{identifier: "finance:invoices"})
    end
  end
end
