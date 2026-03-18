defmodule KsefHub.EmojiGenerator.Behaviour do
  @moduledoc "Behaviour for emoji generation from category context."

  @type category_context :: %{
          identifier: String.t(),
          name: String.t() | nil,
          description: String.t() | nil,
          examples: String.t() | nil
        }

  @callback generate_emoji(context :: category_context()) ::
              {:ok, String.t()} | {:error, term()}
end
