defmodule KsefHub.Credentials.Pkcs12ConverterTest do
  use ExUnit.Case, async: true

  alias KsefHub.Credentials.Pkcs12Converter.Openssl

  @fixtures_dir "test/support/fixtures"

  describe "convert/3 with unencrypted key" do
    test "produces a valid PKCS12 bundle" do
      key_data = File.read!(Path.join(@fixtures_dir, "test_cert.key"))
      crt_data = File.read!(Path.join(@fixtures_dir, "test_cert.crt"))

      assert {:ok, %{p12_data: p12_data, p12_password: password}} =
               Openssl.convert(key_data, crt_data, nil)

      assert is_binary(p12_data)
      assert byte_size(p12_data) > 0
      assert is_binary(password)
      assert String.length(password) > 0
    end
  end

  describe "convert/3 with encrypted key" do
    test "produces a valid PKCS12 bundle when passphrase is correct" do
      key_data = File.read!(Path.join(@fixtures_dir, "test_cert_encrypted.key"))
      crt_data = File.read!(Path.join(@fixtures_dir, "test_cert.crt"))

      assert {:ok, %{p12_data: p12_data, p12_password: password}} =
               Openssl.convert(key_data, crt_data, "testpass123")

      assert is_binary(p12_data)
      assert byte_size(p12_data) > 0
      assert is_binary(password)
    end
  end

  describe "convert/3 error cases" do
    test "returns error for mismatched key and certificate" do
      key_data = File.read!(Path.join(@fixtures_dir, "test_cert_other.key"))
      crt_data = File.read!(Path.join(@fixtures_dir, "test_cert.crt"))

      assert {:error, _reason} = Openssl.convert(key_data, crt_data, nil)
    end

    test "returns error for invalid key data" do
      crt_data = File.read!(Path.join(@fixtures_dir, "test_cert.crt"))

      assert {:error, _reason} = Openssl.convert("not-a-key", crt_data, nil)
    end

    test "returns error for invalid certificate data" do
      key_data = File.read!(Path.join(@fixtures_dir, "test_cert.key"))

      assert {:error, _reason} = Openssl.convert(key_data, "not-a-cert", nil)
    end
  end
end
