defmodule KsefHub.XadesSigner.AuthTokenRequest do
  @moduledoc """
  Builds the AuthTokenRequest XML document for KSeF v2 XADES authentication.
  This XML is signed with xmlsec1 before submission to KSeF.
  """

  @doc """
  Builds an AuthTokenRequest XML string with the given challenge and NIP.
  """
  @spec build(String.t(), String.t()) :: String.t()
  def build(challenge, nip) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <AuthTokenRequest xmlns="http://ksef.mf.gov.pl/auth/token/2.0">
      <Challenge>#{escape_xml(challenge)}</Challenge>
      <ContextIdentifier>
        <Nip>#{escape_xml(nip)}</Nip>
      </ContextIdentifier>
      <SubjectIdentifierType>certificateSubject</SubjectIdentifierType>
    </AuthTokenRequest>
    """
  end

  @spec escape_xml(String.t()) :: String.t()
  defp escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
