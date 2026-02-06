defmodule KsefHub.XadesSigner.AuthTokenRequest do
  @moduledoc """
  Builds the AuthTokenRequest XML document for KSeF XADES authentication.
  This XML is signed with xmlsec1 before submission to KSeF.
  """

  @doc """
  Builds an AuthTokenRequest XML string with the given challenge and NIP.
  """
  def build(challenge, nip) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <AuthorisationChallengeRequest xmlns="http://ksef.mf.gov.pl/schema/gtw/svc/online/types/2021/10/01/0001">
      <ContextIdentifier>
        <Type>onip</Type>
        <Identifier>#{escape_xml(nip)}</Identifier>
      </ContextIdentifier>
      <Challenge>#{escape_xml(challenge)}</Challenge>
    </AuthorisationChallengeRequest>
    """
  end

  defp escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
