defmodule KsefHub.Credentials.CertificateInfo.OpensslTest do
  @moduledoc false
  use ExUnit.Case, async: true

  @moduletag :integration

  alias KsefHub.Credentials.CertificateInfo.Openssl

  describe "extract/2" do
    test "extracts subject and expiry from a PKCS12 generated from test fixtures" do
      key_data = File.read!("test/support/fixtures/test_cert.key")
      crt_data = File.read!("test/support/fixtures/test_cert.crt")

      # First, create a PKCS12 from the test key + crt
      {:ok, %{p12_data: p12_data, p12_password: p12_password}} =
        KsefHub.Credentials.Pkcs12Converter.Openssl.convert(key_data, crt_data, nil)

      assert {:ok, %{subject: subject, expires_at: %Date{} = expires_at}} =
               Openssl.extract(p12_data, p12_password)

      assert is_binary(subject)
      assert String.length(subject) > 0
      assert Date.compare(expires_at, ~D[2000-01-01]) == :gt
    end

    test "returns error for invalid PKCS12 data" do
      assert {:error, _reason} = Openssl.extract("not-a-pkcs12", "password")
    end
  end
end
