defmodule KsefHub.XadesSigner.Native do
  @moduledoc """
  Pure Elixir XADES-BES signer for KSeF authentication.

  Uses OTP's `:crypto` and `:public_key` modules for signing (no xmlsec1 dependency).
  Uses `openssl` CLI only for PKCS12 extraction (same dependency as `CertificateInfo.Openssl`).

  Produces an enveloped XML signature with XAdES QualifyingProperties containing:
  - Two references in SignedInfo: document (URI="") and SignedProperties (URI="#SignedProps-1")
  - SignedProperties with SigningTime and SigningCertificate (SHA-256 digest, issuer DN, serial)
  - Exclusive C14N canonicalization
  - ECDSA-SHA256 signature
  """

  @behaviour KsefHub.XadesSigner.Behaviour

  require Logger
  require Record

  Record.defrecord(
    :otp_certificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecord(
    :otp_tbscertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  alias KsefHub.SecureTemp
  alias KsefHub.XadesSigner.AuthTokenRequest

  @doc """
  Signs a KSeF authentication challenge with XADES-BES using a PKCS12 certificate.

  Extracts the EC private key and certificate from the PKCS12 bundle, then produces
  an enveloped XML signature over the `AuthTokenRequest` document.

  ## Parameters

    - `challenge` — challenge string returned by `KsefClient.get_challenge/0`
    - `nip` — company NIP (tax identification number)
    - `certificate_data` — raw PKCS12 binary (`.p12` file contents)
    - `certificate_password` — password protecting the PKCS12 bundle

  ## Returns

    - `{:ok, signed_xml}` — complete signed AuthTokenRequest XML string
    - `{:error, reason}` — PKCS12 extraction or signing failed
  """
  @impl true
  @spec sign_challenge(String.t(), String.t(), binary(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def sign_challenge(challenge, nip, certificate_data, certificate_password) do
    with {:ok, {ec_key, cert_der}} <- decode_pkcs12(certificate_data, certificate_password),
         {:ok, cert_meta} <- extract_cert_metadata(cert_der) do
      signed_xml = sign_and_assemble(challenge, nip, ec_key, cert_der, cert_meta)
      {:ok, signed_xml}
    end
  rescue
    e ->
      Logger.error("Native XADES signing failed: #{inspect(e)}")
      {:error, {:signing_failed, Exception.message(e)}}
  end

  @spec decode_pkcs12(binary(), String.t()) ::
          {:ok, {binary(), binary()}} | {:error, term()}
  defp decode_pkcs12(p12_data, password) do
    p12_path = SecureTemp.write(p12_data, "cert.p12")
    pass_path = SecureTemp.write(password, "pass.txt")

    try do
      with {:ok, key_pem} <- extract_private_key(p12_path, pass_path),
           {:ok, cert_pem} <- extract_certificate(p12_path, pass_path),
           {:ok, ec_key} <- parse_ec_private_key(key_pem),
           {:ok, cert_der} <- parse_certificate_der(cert_pem) do
        {:ok, {ec_key, cert_der}}
      end
    after
      SecureTemp.delete(p12_path)
      SecureTemp.delete(pass_path)
    end
  end

  @spec extract_private_key(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp extract_private_key(p12_path, pass_path) do
    base_args = [
      "pkcs12",
      "-in",
      p12_path,
      "-passin",
      "file:#{pass_path}",
      "-nocerts",
      "-nodes"
    ]

    case run_openssl(base_args ++ ["-legacy"]) do
      {:ok, output} -> {:ok, output}
      {:error, {:openssl_failed, _}} -> run_openssl(base_args)
      {:error, _} = error -> error
    end
  end

  @spec extract_certificate(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp extract_certificate(p12_path, pass_path) do
    base_args = [
      "pkcs12",
      "-in",
      p12_path,
      "-passin",
      "file:#{pass_path}",
      "-clcerts",
      "-nokeys"
    ]

    case run_openssl(base_args ++ ["-legacy"]) do
      {:ok, output} -> {:ok, output}
      {:error, {:openssl_failed, _}} -> run_openssl(base_args)
      {:error, _} = error -> error
    end
  end

  @spec run_openssl([String.t()]) :: {:ok, String.t()} | {:error, term()}
  defp run_openssl(args) do
    task = Task.async(fn -> System.cmd("openssl", args, stderr_to_stdout: true) end)

    case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {_output, exit_code}} ->
        {:error, {:openssl_failed, exit_code}}

      nil ->
        {:error, :timeout}
    end
  end

  @spec parse_ec_private_key(String.t()) :: {:ok, binary()} | {:error, term()}
  defp parse_ec_private_key(pem) do
    case :public_key.pem_decode(pem) do
      [{:ECPrivateKey, der, :not_encrypted} | _] ->
        extract_ec_private_key_binary(:public_key.der_decode(:ECPrivateKey, der))

      [{:PrivateKeyInfo, der, :not_encrypted} | _] ->
        # PKCS8-wrapped key (openssl outputs this for EC keys)
        extract_ec_private_key_binary(:public_key.der_decode(:PrivateKeyInfo, der))

      [{type, _der, _enc} | _] ->
        {:error, {:unsupported_key_type, type}}

      _ ->
        {:error, :no_private_key_found}
    end
  end

  # :crypto.sign requires the raw private key binary, not the ECPrivateKey record
  @spec extract_ec_private_key_binary(term()) :: {:ok, binary()} | {:error, term()}
  defp extract_ec_private_key_binary({:ECPrivateKey, _, priv_key_bin, _, _, _}) do
    {:ok, priv_key_bin}
  end

  defp extract_ec_private_key_binary(_), do: {:error, :not_ec_key}

  @spec parse_certificate_der(String.t()) :: {:ok, binary()} | {:error, term()}
  defp parse_certificate_der(pem) do
    case :public_key.pem_decode(pem) do
      [{:Certificate, der, :not_encrypted} | _] -> {:ok, der}
      _ -> {:error, :no_certificate_found}
    end
  end

  @spec extract_cert_metadata(binary()) ::
          {:ok,
           %{
             b64: String.t(),
             digest_b64: String.t(),
             issuer_dn: String.t(),
             serial: integer()
           }}
          | {:error, term()}
  defp extract_cert_metadata(cert_der) do
    cert_b64 = Base.encode64(cert_der)
    cert_digest_b64 = :crypto.hash(:sha256, cert_der) |> Base.encode64()

    cert = :public_key.pkix_decode_cert(cert_der, :otp)
    tbs = otp_certificate(cert, :tbsCertificate)
    serial = otp_tbscertificate(tbs, :serialNumber)
    issuer = otp_tbscertificate(tbs, :issuer)
    issuer_dn = format_issuer_dn(issuer)

    {:ok, %{b64: cert_b64, digest_b64: cert_digest_b64, issuer_dn: issuer_dn, serial: serial}}
  rescue
    e ->
      Logger.error("Failed to extract cert metadata: #{inspect(e)}")
      {:error, :cert_metadata_failed}
  end

  @spec format_issuer_dn(term()) :: String.t()
  defp format_issuer_dn({:rdnSequence, rdn_sets}) do
    rdn_sets
    |> List.flatten()
    |> Enum.map(&format_attribute/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
    |> Enum.join(", ")
  end

  defp format_issuer_dn(_), do: "Unknown"

  @spec format_attribute(term()) :: String.t() | nil
  defp format_attribute({:AttributeTypeAndValue, oid, value}) do
    name = oid_to_name(oid)
    decoded = decode_attribute_value(value)

    if name && decoded, do: "#{name}=#{decoded}"
  end

  defp format_attribute(_), do: nil

  @spec oid_to_name(tuple()) :: String.t() | nil
  defp oid_to_name({2, 5, 4, 3}), do: "CN"
  defp oid_to_name({2, 5, 4, 6}), do: "C"
  defp oid_to_name({2, 5, 4, 7}), do: "L"
  defp oid_to_name({2, 5, 4, 8}), do: "ST"
  defp oid_to_name({2, 5, 4, 10}), do: "O"
  defp oid_to_name({2, 5, 4, 11}), do: "OU"
  defp oid_to_name({2, 5, 4, 5}), do: "SERIALNUMBER"
  defp oid_to_name(_), do: nil

  @spec decode_attribute_value(term()) :: String.t() | nil
  defp decode_attribute_value({:utf8String, value}) when is_binary(value), do: value
  defp decode_attribute_value({:printableString, value}) when is_list(value), do: to_string(value)
  defp decode_attribute_value({:printableString, value}) when is_binary(value), do: value
  defp decode_attribute_value({:ia5String, value}) when is_list(value), do: to_string(value)
  defp decode_attribute_value({:ia5String, value}) when is_binary(value), do: value
  defp decode_attribute_value(value) when is_binary(value), do: value
  defp decode_attribute_value(value) when is_list(value), do: to_string(value)
  defp decode_attribute_value(_), do: nil

  @spec sign_and_assemble(String.t(), String.t(), binary(), binary(), map()) :: String.t()
  defp sign_and_assemble(challenge, nip, ec_key, _cert_der, cert_meta) do
    # 1. Body digest (enveloped-signature transform = document without <Signature>)
    body_xml = AuthTokenRequest.build_body(challenge, nip)
    body_digest = :crypto.hash(:sha256, body_xml) |> Base.encode64()

    # 2. SignedProperties digest
    signing_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    props_xml = build_signed_properties(signing_time, cert_meta)
    props_digest = :crypto.hash(:sha256, props_xml) |> Base.encode64()

    # 3. Sign SignedInfo
    signed_info_xml = build_signed_info(body_digest, props_digest)
    signature_der = :crypto.sign(:ecdsa, :sha256, signed_info_xml, [ec_key, :secp256r1])
    signature_raw = der_signature_to_raw(signature_der, 32)
    signature_b64 = Base.encode64(signature_raw)

    # 4. Assemble final XML
    assemble_signed_xml(challenge, nip, signed_info_xml, signature_b64, cert_meta, props_xml)
  end

  # Builds SignedProperties in Exclusive C14N canonical form.
  #
  # Per Exclusive C14N, xmlns:ds is NOT on <xades:SignedProperties> (it doesn't
  # visibly utilize the ds: prefix). Instead, xmlns:ds appears on each ds:* element
  # individually, since no ancestor within the canonicalized subtree has it.
  @spec build_signed_properties(String.t(), map()) :: String.t()
  defp build_signed_properties(signing_time, cert_meta) do
    ds = ~s( xmlns:ds="http://www.w3.org/2000/09/xmldsig#")

    ~s(<xades:SignedProperties xmlns:xades="http://uri.etsi.org/01903/v1.3.2#" Id="SignedProps-1">) <>
      "<xades:SignedSignatureProperties>" <>
      "<xades:SigningTime>#{signing_time}</xades:SigningTime>" <>
      "<xades:SigningCertificate>" <>
      "<xades:Cert>" <>
      "<xades:CertDigest>" <>
      ~s(<ds:DigestMethod#{ds} Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod>) <>
      "<ds:DigestValue#{ds}>#{cert_meta.digest_b64}</ds:DigestValue>" <>
      "</xades:CertDigest>" <>
      "<xades:IssuerSerial>" <>
      "<ds:X509IssuerName#{ds}>#{escape_xml(cert_meta.issuer_dn)}</ds:X509IssuerName>" <>
      "<ds:X509SerialNumber#{ds}>#{cert_meta.serial}</ds:X509SerialNumber>" <>
      "</xades:IssuerSerial>" <>
      "</xades:Cert>" <>
      "</xades:SigningCertificate>" <>
      "</xades:SignedSignatureProperties>" <>
      "</xades:SignedProperties>"
  end

  @spec build_signed_info(String.t(), String.t()) :: String.t()
  defp build_signed_info(body_digest_b64, props_digest_b64) do
    ~s(<ds:SignedInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">) <>
      ~s(<ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"></ds:CanonicalizationMethod>) <>
      ~s(<ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"></ds:SignatureMethod>) <>
      ~s(<ds:Reference URI="">) <>
      "<ds:Transforms>" <>
      ~s(<ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"></ds:Transform>) <>
      ~s(<ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"></ds:Transform>) <>
      "</ds:Transforms>" <>
      ~s(<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod>) <>
      "<ds:DigestValue>#{body_digest_b64}</ds:DigestValue>" <>
      "</ds:Reference>" <>
      ~s(<ds:Reference Type="http://uri.etsi.org/01903#SignedProperties" URI="#SignedProps-1">) <>
      "<ds:Transforms>" <>
      ~s(<ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"></ds:Transform>) <>
      "</ds:Transforms>" <>
      ~s(<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod>) <>
      "<ds:DigestValue>#{props_digest_b64}</ds:DigestValue>" <>
      "</ds:Reference>" <>
      "</ds:SignedInfo>"
  end

  @spec assemble_signed_xml(String.t(), String.t(), String.t(), String.t(), map(), String.t()) ::
          String.t()
  defp assemble_signed_xml(challenge, nip, signed_info_xml, signature_b64, cert_meta, props_xml) do
    # Remove the xmlns:ds from SignedInfo for the assembled document
    # (it will be on the parent ds:Signature element instead)
    inner_signed_info =
      String.replace(signed_info_xml, ~s( xmlns:ds="http://www.w3.org/2000/09/xmldsig#"), "")

    # Remove namespace declarations from SignedProperties for embedded form
    # (both xmlns:ds and xmlns:xades are inherited from parent ds:Signature)
    inner_props =
      props_xml
      |> String.replace(~s( xmlns:ds="http://www.w3.org/2000/09/xmldsig#"), "")
      |> String.replace(~s( xmlns:xades="http://uri.etsi.org/01903/v1.3.2#"), "")

    ~s(<?xml version="1.0" encoding="UTF-8"?>) <>
      ~s(<AuthTokenRequest xmlns="http://ksef.mf.gov.pl/auth/token/2.0">) <>
      "<Challenge>#{escape_xml(challenge)}</Challenge>" <>
      "<ContextIdentifier>" <>
      "<Nip>#{escape_xml(nip)}</Nip>" <>
      "</ContextIdentifier>" <>
      "<SubjectIdentifierType>certificateSubject</SubjectIdentifierType>" <>
      ~s(<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#" xmlns:xades="http://uri.etsi.org/01903/v1.3.2#" Id="Signature">) <>
      inner_signed_info <>
      "<ds:SignatureValue>#{signature_b64}</ds:SignatureValue>" <>
      "<ds:KeyInfo>" <>
      "<ds:X509Data>" <>
      "<ds:X509Certificate>#{cert_meta.b64}</ds:X509Certificate>" <>
      "</ds:X509Data>" <>
      "</ds:KeyInfo>" <>
      "<ds:Object>" <>
      ~s(<xades:QualifyingProperties Target="#Signature">) <>
      inner_props <>
      "</xades:QualifyingProperties>" <>
      "</ds:Object>" <>
      "</ds:Signature>" <>
      "</AuthTokenRequest>"
  end

  # Converts DER-encoded ECDSA signature to raw r||s format (IEEE P1363).
  # XML Digital Signature 1.1 expects r||s, each zero-padded to `byte_len`.
  # For P-256: byte_len=32, so output is always 64 bytes.
  @spec der_signature_to_raw(binary(), pos_integer()) :: binary()
  defp der_signature_to_raw(der, byte_len) do
    <<0x30, _seq_len::8, 0x02, r_len::8, r_bytes::binary-size(r_len), 0x02, s_len::8,
      s_bytes::binary-size(s_len)>> = der

    pad_or_trim(r_bytes, byte_len) <> pad_or_trim(s_bytes, byte_len)
  end

  @spec pad_or_trim(binary(), pos_integer()) :: binary()
  defp pad_or_trim(bytes, target) when byte_size(bytes) == target, do: bytes

  defp pad_or_trim(bytes, target) when byte_size(bytes) > target do
    # ASN.1 INTEGER may have a leading 0x00 for positive sign — strip it
    trim = byte_size(bytes) - target
    <<_::binary-size(trim), trimmed::binary-size(target)>> = bytes
    trimmed
  end

  defp pad_or_trim(bytes, target) when byte_size(bytes) < target do
    pad = target - byte_size(bytes)
    :binary.copy(<<0>>, pad) <> bytes
  end

  defdelegate escape_xml(str), to: AuthTokenRequest
end
