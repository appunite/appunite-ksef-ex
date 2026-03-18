defmodule KsefHub.EmojiGenerator.ClientTest do
  use ExUnit.Case, async: true

  alias KsefHub.EmojiGenerator.Client

  @context %{identifier: "finance:invoices", name: nil, description: nil, examples: nil}

  describe "generate_emoji/1" do
    test "returns error when API key is not configured" do
      Application.put_env(:ksef_hub, :anthropic_api_key, nil)

      assert {:error, :missing_api_key} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "returns error when API key is empty string" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "")

      assert {:error, :missing_api_key} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "returns emoji on successful API response" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "💰"}]
        })
      end)

      assert {:ok, "💰"} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "extracts emoji from response with surrounding text" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "Here's the emoji: 📦"}]
        })
      end)

      assert {:ok, "📦"} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "returns error when response contains no emoji" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "I cannot pick one"}]
        })
      end)

      assert {:error, :no_emoji_in_response} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "returns error on non-200 API response" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => %{"message" => "rate limited"}})
      end)

      assert {:error, {:api_error, 429}} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "returns error on request failure" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, {:request_failed, _}} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "includes all context fields in prompt" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        [%{"content" => prompt}] = decoded["messages"]

        assert prompt =~ "Identifier: finance:invoices"
        assert prompt =~ "Name: Invoices"
        assert prompt =~ "Description: Invoice processing"
        assert prompt =~ "Examples: Monthly recurring"

        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "💰"}]
        })
      end)

      context = %{
        identifier: "finance:invoices",
        name: "Invoices",
        description: "Invoice processing",
        examples: "Monthly recurring"
      }

      assert {:ok, "💰"} = Client.generate_emoji(context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end

    test "omits nil/empty context fields from prompt" do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        [%{"content" => prompt}] = decoded["messages"]

        assert prompt =~ "Identifier: finance:invoices"
        refute prompt =~ "Name:"
        refute prompt =~ "Description:"
        refute prompt =~ "Examples:"

        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "💰"}]
        })
      end)

      assert {:ok, "💰"} = Client.generate_emoji(@context)
    after
      Application.delete_env(:ksef_hub, :anthropic_api_key)
    end
  end

  describe "extract_first_emoji (via generate_emoji)" do
    setup do
      Application.put_env(:ksef_hub, :anthropic_api_key, "test-key")

      on_exit(fn ->
        Application.delete_env(:ksef_hub, :anthropic_api_key)
      end)
    end

    test "handles emoji with variation selector" do
      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "☀️"}]})
      end)

      assert {:ok, "☀️"} = Client.generate_emoji(@context)
    end

    test "handles empty response text" do
      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => ""}]})
      end)

      assert {:error, :no_emoji_in_response} = Client.generate_emoji(@context)
    end

    test "picks first emoji when preceded by text" do
      Req.Test.stub(KsefHub.EmojiGenerator.Client, fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "I think 💰 is best"}]})
      end)

      assert {:ok, "💰"} = Client.generate_emoji(@context)
    end
  end
end
