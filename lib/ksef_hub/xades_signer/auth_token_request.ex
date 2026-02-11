defmodule KsefHub.XadesSigner.AuthTokenRequest do
  @moduledoc """
  Builds the AuthTokenRequest XML document for KSeF v2 XADES authentication.
  This XML includes a ds:Signature template that xmlsec1 fills in during signing.
  """

  @doc """
  Builds an AuthTokenRequest XML string with an enveloped signature template.
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
      <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#" Id="Signature">
        <ds:SignedInfo>
          <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
          <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"/>
          <ds:Reference URI="">
            <ds:Transforms>
              <ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
              <ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
            </ds:Transforms>
            <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
            <ds:DigestValue/>
          </ds:Reference>
        </ds:SignedInfo>
        <ds:SignatureValue/>
        <ds:KeyInfo>
          <ds:X509Data>
            <ds:X509Certificate/>
          </ds:X509Data>
        </ds:KeyInfo>
      </ds:Signature>
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
