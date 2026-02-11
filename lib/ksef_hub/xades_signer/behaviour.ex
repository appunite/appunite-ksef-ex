defmodule KsefHub.XadesSigner.Behaviour do
  @moduledoc """
  Behaviour for XADES XML signing. Implementations: Native (production) and Mock (test).
  """

  @callback sign_challenge(
              challenge :: String.t(),
              nip :: String.t(),
              certificate_data :: binary(),
              certificate_password :: String.t()
            ) :: {:ok, String.t()} | {:error, term()}
end
