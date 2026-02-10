defmodule KsefHub.Credentials.CertificateInfo.Openssl do
  @moduledoc """
  Extracts certificate metadata (subject, expiry) from a PKCS12 file using `openssl` CLI
  and Erlang's `:public_key` module.

  Uses secure temp files with `0600` permissions, cleaned up after use.
  Passes passwords via file (not CLI arguments) to avoid exposure in `ps`.
  """

  @behaviour KsefHub.Credentials.CertificateInfo.Behaviour

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

  @doc """
  Extracts the subject and expiry date from a PKCS12 binary.

  Writes the PKCS12 data and password to secure temp files, invokes
  `openssl pkcs12` to extract the PEM certificate, then parses it
  with Erlang's `:public_key` module.

  Returns `{:ok, %{subject: String.t(), expires_at: Date.t()}}` on success,
  or `{:error, term()}` on failure.
  """
  @impl true
  @spec extract(binary(), String.t()) ::
          {:ok, %{subject: String.t(), expires_at: Date.t()}} | {:error, term()}
  def extract(p12_data, password) do
    p12_path = SecureTemp.write(p12_data, "cert.p12")
    pass_path = SecureTemp.write(password, "pass.txt")

    try do
      with {:ok, pem_output} <- extract_pem(p12_path, pass_path),
           {:ok, cert} <- decode_pem_certificate(pem_output) do
        parse_certificate(cert)
      end
    after
      SecureTemp.delete(p12_path)
      SecureTemp.delete(pass_path)
    end
  end

  @spec extract_pem(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp extract_pem(p12_path, pass_path) do
    base_args = ["pkcs12", "-in", p12_path, "-passin", "file:#{pass_path}", "-clcerts", "-nokeys"]

    case run_openssl(base_args ++ ["-legacy"]) do
      {:ok, output} ->
        {:ok, output}

      {:error, {:openssl_failed, _}} ->
        # Retry without -legacy flag for older OpenSSL versions
        run_openssl(base_args)

      {:error, _} = error ->
        error
    end
  end

  @spec run_openssl([String.t()]) :: {:ok, String.t()} | {:error, term()}
  defp run_openssl(args) do
    task = Task.async(fn -> System.cmd("openssl", args, stderr_to_stdout: true) end)

    case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {_output, exit_code}} ->
        Logger.warning("openssl pkcs12 info extraction failed (exit #{exit_code})")
        {:error, {:openssl_failed, exit_code}}

      nil ->
        Logger.warning("openssl pkcs12 info extraction timed out")
        {:error, :timeout}
    end
  end

  @spec decode_pem_certificate(String.t()) ::
          {:ok, :public_key.der_encoded()} | {:error, :no_certificate_found}
  defp decode_pem_certificate(pem_output) do
    case :public_key.pem_decode(pem_output) do
      [{:Certificate, der, :not_encrypted} | _] -> {:ok, der}
      _ -> {:error, :no_certificate_found}
    end
  end

  @spec parse_certificate(:public_key.der_encoded()) ::
          {:ok, %{subject: String.t(), not_before: Date.t(), expires_at: Date.t()}}
          | {:error, term()}
  defp parse_certificate(der) do
    cert = :public_key.pkix_decode_cert(der, :otp)
    tbs = otp_certificate(cert, :tbsCertificate)
    validity = otp_tbscertificate(tbs, :validity)
    subject = otp_tbscertificate(tbs, :subject)

    {:Validity, not_before_raw, not_after_raw} = validity
    subject_string = format_subject(subject)
    not_before = parse_validity_time(not_before_raw)
    expires_at = parse_validity_time(not_after_raw)

    {:ok, %{subject: subject_string, not_before: not_before, expires_at: expires_at}}
  rescue
    _e ->
      Logger.warning("Failed to parse certificate")
      {:error, :parse_failed}
  end

  @spec format_subject(term()) :: String.t()
  defp format_subject({:rdnSequence, rdn_sets}) do
    rdn_sets
    |> List.flatten()
    |> Enum.map(&format_attribute/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
    |> Enum.join(", ")
  end

  defp format_subject(_), do: "Unknown"

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

  @spec parse_validity_time(term()) :: Date.t()
  defp parse_validity_time({:utcTime, time}) do
    time
    |> to_string()
    |> parse_utc_time()
  end

  defp parse_validity_time({:generalTime, time}) do
    time
    |> to_string()
    |> parse_general_time()
  end

  @spec parse_utc_time(String.t()) :: Date.t()
  defp parse_utc_time(
         <<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2), _rest::binary>>
       ) do
    year = String.to_integer(yy)
    # UTCTime uses 2-digit years: 00-49 = 2000-2049, 50-99 = 1950-1999
    full_year = if year >= 50, do: 1900 + year, else: 2000 + year
    Date.new!(full_year, String.to_integer(mm), String.to_integer(dd))
  end

  @spec parse_general_time(String.t()) :: Date.t()
  defp parse_general_time(
         <<yyyy::binary-size(4), mm::binary-size(2), dd::binary-size(2), _rest::binary>>
       ) do
    Date.new!(String.to_integer(yyyy), String.to_integer(mm), String.to_integer(dd))
  end
end
