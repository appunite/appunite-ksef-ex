defmodule KsefHub.EmojiGenerator.Client do
  @moduledoc """
  Anthropic Messages API client for emoji generation.

  Uses Claude Haiku to suggest a single emoji for a given category context.
  """

  @behaviour KsefHub.EmojiGenerator.Behaviour

  require Logger

  @model "claude-haiku-4-5-20251001"

  @doc "Calls Claude Haiku to generate a single emoji for the given category context."
  @spec generate_emoji(KsefHub.EmojiGenerator.Behaviour.category_context()) ::
          {:ok, String.t()} | {:error, term()}
  @impl true
  def generate_emoji(context) do
    api_key = Application.get_env(:ksef_hub, :anthropic_api_key)

    if is_nil(api_key) or api_key == "" do
      Logger.warning("[EmojiGenerator] ANTHROPIC_API_KEY not configured, skipping")
      {:error, :missing_api_key}
    else
      do_generate(context)
    end
  end

  @spec do_generate(map()) :: {:ok, String.t()} | {:error, term()}
  defp do_generate(context) do
    user_content = build_prompt(context)

    body =
      Jason.encode!(%{
        model: @model,
        max_tokens: 16,
        messages: [%{role: "user", content: user_content}]
      })

    Logger.debug(
      "[EmojiGenerator] Requesting emoji for #{inspect(context.identifier)} model=#{@model}"
    )

    case Req.post(req(), url: "/v1/messages", body: body) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        emoji = text |> String.trim() |> extract_first_emoji()

        if emoji do
          Logger.info("[EmojiGenerator] Generated #{emoji} for #{inspect(context.identifier)}")
          {:ok, emoji}
        else
          Logger.warning(
            "[EmojiGenerator] No emoji found in response #{inspect(text)} for #{inspect(context.identifier)}"
          )

          {:error, :no_emoji_in_response}
        end

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("[EmojiGenerator] API error status=#{status} body=#{inspect(resp_body)}")

        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.warning("[EmojiGenerator] Request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @spec build_prompt(map()) :: String.t()
  defp build_prompt(context) do
    details =
      [
        {"Identifier", context.identifier},
        {"Name", context[:name]},
        {"Description", context[:description]},
        {"Examples", context[:examples]}
      ]
      |> Enum.reject(fn {_label, value} -> is_nil(value) or value == "" end)
      |> Enum.map_join("\n", fn {label, value} -> "#{label}: #{value}" end)

    "Pick exactly ONE emoji that best represents this invoice category. Reply with only the emoji, nothing else.\n\n#{details}"
  end

  @spec extract_first_emoji(String.t()) :: String.t() | nil
  defp extract_first_emoji(text) do
    # Match the first emoji (including compound/ZWJ sequences)
    case Regex.run(~r/\p{So}[\p{Mn}\p{Me}\x{FE0F}\x{200D}\p{So}\p{Sk}]*/u, text) do
      [emoji | _] -> emoji
      nil -> nil
    end
  end

  @spec req() :: Req.Request.t()
  defp req do
    api_key = Application.get_env(:ksef_hub, :anthropic_api_key)
    options = Application.get_env(:ksef_hub, :emoji_generator_req_options, [])

    Req.new(
      [
        base_url: "https://api.anthropic.com",
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", "2023-06-01"},
          {"content-type", "application/json"}
        ],
        receive_timeout: 10_000
      ] ++ options
    )
  end
end
