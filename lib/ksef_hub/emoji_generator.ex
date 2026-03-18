defmodule KsefHub.EmojiGenerator do
  @moduledoc "Context for AI-powered emoji generation for categories."

  @doc "Generates an emoji for the given category context."
  @spec generate_emoji(KsefHub.EmojiGenerator.Behaviour.category_context()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_emoji(context) do
    client().generate_emoji(context)
  end

  @spec client() :: module()
  defp client, do: Application.get_env(:ksef_hub, :emoji_generator, KsefHub.EmojiGenerator.Client)
end
