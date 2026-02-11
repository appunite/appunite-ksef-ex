defmodule KsefHub.XadesSigner.NativeTest do
  use ExUnit.Case, async: true

  alias KsefHub.XadesSigner.Native

  @challenge "20250211-test-challenge-abc123"
  @nip "1234567890"

  describe "sign_challenge/4" do
    setup do
      {p12_data, password} = generate_test_pkcs12()
      %{p12_data: p12_data, password: password}
    end

    test "returns {:ok, signed_xml} with valid PKCS12", %{p12_data: p12_data, password: password} do
      assert {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)
      assert is_binary(signed_xml)
    end

    test "signed XML contains XML declaration", %{p12_data: p12_data, password: password} do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)
      assert String.starts_with?(signed_xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    end

    test "signed XML contains AuthTokenRequest with challenge and NIP", %{
      p12_data: p12_data,
      password: password
    } do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)
      assert signed_xml =~ "<Challenge>#{@challenge}</Challenge>"
      assert signed_xml =~ "<Nip>#{@nip}</Nip>"
      assert signed_xml =~ "<SubjectIdentifierType>certificateSubject</SubjectIdentifierType>"
    end

    test "signed XML contains ds:Signature with SignatureValue", %{
      p12_data: p12_data,
      password: password
    } do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)
      assert signed_xml =~ "<ds:Signature"
      assert signed_xml =~ "<ds:SignatureValue>"
      assert signed_xml =~ "</ds:SignatureValue>"

      # SignatureValue should be non-empty Base64
      [_, sig_value] = Regex.run(~r/<ds:SignatureValue>([^<]+)</, signed_xml)
      assert {:ok, _} = Base.decode64(sig_value)
      assert byte_size(sig_value) > 0
    end

    test "signed XML contains X509Certificate", %{p12_data: p12_data, password: password} do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)
      assert signed_xml =~ "<ds:X509Certificate>"

      [_, cert_b64] = Regex.run(~r/<ds:X509Certificate>([^<]+)</, signed_xml)
      assert {:ok, cert_der} = Base.decode64(cert_b64)
      # Should be a valid DER certificate
      assert {:OTPCertificate, _, _, _} = :public_key.pkix_decode_cert(cert_der, :otp)
    end

    test "signed XML contains XAdES QualifyingProperties", %{
      p12_data: p12_data,
      password: password
    } do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)
      assert signed_xml =~ "<xades:QualifyingProperties"
      assert signed_xml =~ "<xades:SignedProperties"
      assert signed_xml =~ "Id=\"SignedProps-1\""
      assert signed_xml =~ "<xades:SigningTime>"
      assert signed_xml =~ "<xades:SigningCertificate>"
      assert signed_xml =~ "<xades:CertDigest>"
      assert signed_xml =~ "<xades:IssuerSerial>"
    end

    test "signed XML contains correct algorithm URIs", %{
      p12_data: p12_data,
      password: password
    } do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)

      # Exclusive C14N
      assert signed_xml =~ "http://www.w3.org/2001/10/xml-exc-c14n#"
      # ECDSA-SHA256
      assert signed_xml =~ "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
      # SHA-256 digest
      assert signed_xml =~ "http://www.w3.org/2001/04/xmlenc#sha256"
      # Enveloped signature transform
      assert signed_xml =~ "http://www.w3.org/2000/09/xmldsig#enveloped-signature"
    end

    test "signed XML has two references in SignedInfo", %{
      p12_data: p12_data,
      password: password
    } do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)

      # Reference URI="" (document)
      assert signed_xml =~ "<ds:Reference URI=\"\">"
      # Reference URI="#SignedProps-1" (signed properties)
      assert signed_xml =~ "URI=\"#SignedProps-1\""
    end

    test "signature is verifiable with the embedded certificate", %{
      p12_data: p12_data,
      password: password
    } do
      {:ok, signed_xml} = Native.sign_challenge(@challenge, @nip, p12_data, password)

      # Extract SignatureValue (raw r||s format, 64 bytes for P-256)
      [_, sig_b64] = Regex.run(~r/<ds:SignatureValue>([^<]+)</, signed_xml)
      signature_raw = Base.decode64!(sig_b64)
      assert byte_size(signature_raw) == 64

      # Convert r||s back to DER for :crypto.verify
      <<r::binary-size(32), s::binary-size(32)>> = signature_raw
      r_der = der_integer(r)
      s_der = der_integer(s)
      seq_content = r_der <> s_der
      signature_der = <<0x30, byte_size(seq_content)::8>> <> seq_content

      # Extract certificate and get public key point (uncompressed EC point)
      [_, cert_b64] = Regex.run(~r/<ds:X509Certificate>([^<]+)</, signed_xml)
      cert_der = Base.decode64!(cert_b64)
      cert = :public_key.pkix_decode_cert(cert_der, :otp)

      {:OTPCertificate,
       {:OTPTBSCertificate, _, _, _, _, _, _,
        {:OTPSubjectPublicKeyInfo, _, {:ECPoint, ec_point_bin}}, _, _, _}, _, _} = cert

      # Reconstruct canonical SignedInfo (with xmlns:ds on element)
      [_, signed_info_content] =
        Regex.run(~r/<ds:SignedInfo>(.*?)<\/ds:SignedInfo>/s, signed_xml)

      signed_info_xml =
        "<ds:SignedInfo xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">" <>
          signed_info_content <> "</ds:SignedInfo>"

      # :crypto.verify expects [ec_point_binary, :secp256r1] for ECDSA
      assert :crypto.verify(:ecdsa, :sha256, signed_info_xml, signature_der, [
               ec_point_bin,
               :secp256r1
             ])
    end

    test "returns error for invalid PKCS12 data" do
      assert {:error, _} = Native.sign_challenge(@challenge, @nip, "not-a-pkcs12", "password")
    end

    test "returns error for wrong password", %{p12_data: p12_data} do
      assert {:error, _} = Native.sign_challenge(@challenge, @nip, p12_data, "wrong-password")
    end
  end

  # Encode a raw big-endian integer as ASN.1 DER INTEGER
  @spec der_integer(binary()) :: binary()
  defp der_integer(bytes) do
    # Strip leading zeros
    trimmed = String.trim_leading(bytes, <<0>>)
    trimmed = if trimmed == "", do: <<0>>, else: trimmed

    # Add leading 0x00 if high bit is set (ASN.1 positive integer)
    padded = if :binary.first(trimmed) >= 128, do: <<0>> <> trimmed, else: trimmed
    <<0x02, byte_size(padded)::8>> <> padded
  end

  # Generate a self-signed ECDSA P-256 certificate and PKCS12 bundle for testing
  @spec generate_test_pkcs12() :: {binary(), String.t()}
  defp generate_test_pkcs12 do
    password = "test-password-123"
    tmp_dir = System.tmp_dir!()
    key_path = Path.join(tmp_dir, "ksef_test_#{:rand.uniform(999_999)}_key.pem")
    cert_path = Path.join(tmp_dir, "ksef_test_#{:rand.uniform(999_999)}_cert.pem")
    p12_path = Path.join(tmp_dir, "ksef_test_#{:rand.uniform(999_999)}_cert.p12")

    try do
      # Generate EC P-256 private key
      {_, 0} =
        System.cmd("openssl", ["ecparam", "-genkey", "-name", "prime256v1", "-out", key_path])

      # Generate self-signed certificate
      {_, 0} =
        System.cmd("openssl", [
          "req",
          "-new",
          "-x509",
          "-key",
          key_path,
          "-out",
          cert_path,
          "-days",
          "1",
          "-subj",
          "/CN=Test KSeF/O=Test Org/C=PL"
        ])

      # Create PKCS12 bundle
      {_, 0} =
        System.cmd("openssl", [
          "pkcs12",
          "-export",
          "-in",
          cert_path,
          "-inkey",
          key_path,
          "-out",
          p12_path,
          "-passout",
          "pass:#{password}"
        ])

      p12_data = File.read!(p12_path)
      {p12_data, password}
    after
      File.rm(key_path)
      File.rm(cert_path)
      File.rm(p12_path)
    end
  end
end
