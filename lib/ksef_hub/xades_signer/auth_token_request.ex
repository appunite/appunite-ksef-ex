defmodule KsefHub.XadesSigner.AuthTokenRequest do
  @moduledoc """
  Builds the canonical AuthTokenRequest body XML for KSeF v2 XADES authentication.
  """

  @doc """
  Builds the canonical AuthTokenRequest body XML without signature or XML declaration.

  This is the document content that gets digested per the enveloped-signature transform:
  the full `<AuthTokenRequest>` element with its children, but without any `<ds:Signature>`
  element and without the `<?xml ...?>` declaration.

  Canonical form: no extra whitespace between tags, explicit close tags.
  """
  @spec build_body(String.t(), String.t()) :: String.t()
  def build_body(challenge, nip) do
    "<AuthTokenRequest xmlns=\"http://ksef.mf.gov.pl/auth/token/2.0\">" <>
      "<Challenge>#{escape_xml(challenge)}</Challenge>" <>
      "<ContextIdentifier>" <>
      "<Nip>#{escape_xml(nip)}</Nip>" <>
      "</ContextIdentifier>" <>
      "<SubjectIdentifierType>certificateSubject</SubjectIdentifierType>" <>
      "</AuthTokenRequest>"
  end

  @doc """
  Escapes XML special characters in a string.
  """
  @spec escape_xml(String.t()) :: String.t()
  def escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
