defmodule KsefHub.Pdf.Xsltproc do
  @moduledoc """
  Wraps xsltproc CLI to transform FA(3) XML into HTML using gov.pl stylesheets.
  Uses secure temp files with 0600 permissions, cleaned up after use.
  """

  require Logger

  @cmd_timeout 30_000
  @xsl_path Path.join(:code.priv_dir(:ksef_hub), "xsl/fa3-styl.xsl")

  @doc """
  Transforms FA(3) XML content into HTML using the gov.pl XSL stylesheet.
  Returns `{:ok, html}` or `{:error, reason}`.
  """
  @spec transform(String.t()) :: {:ok, String.t()} | {:error, term()}
  def transform(xml_content) when is_binary(xml_content) do
    xsl_path = xsl_path()

    unless File.exists?(xsl_path) do
      {:error, :xsl_not_found}
    else
      do_transform(xml_content, xsl_path)
    end
  end

  defp do_transform(xml_content, xsl_path) do
    xml_path = write_secure_temp(xml_content, "invoice.xml")

    try do
      case System.cmd("xsltproc", ["--nonet", xsl_path, xml_path],
             timeout: @cmd_timeout,
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          {:ok, output}

        {output, exit_code} ->
          Logger.error("xsltproc failed (exit #{exit_code}): #{output}")
          {:error, {:xsltproc_failed, exit_code, output}}
      end
    rescue
      e in ErlangError ->
        Logger.error("xsltproc not available: #{inspect(e)}")
        {:error, :xsltproc_not_available}
    after
      secure_delete(xml_path)
    end
  end

  defp xsl_path do
    Application.get_env(:ksef_hub, :xsl_path, @xsl_path)
  end

  defp write_secure_temp(content, suffix) do
    path = temp_path(suffix)
    File.write!(path, content)
    File.chmod!(path, 0o600)
    path
  end

  defp temp_path(suffix) do
    random = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    Path.join(System.tmp_dir!(), "ksef_pdf_#{random}_#{suffix}")
  end

  defp secure_delete(path) do
    if File.exists?(path) do
      case File.stat(path) do
        {:ok, %{size: size}} when size > 0 ->
          File.write(path, :binary.copy(<<0>>, size))

        _ ->
          :ok
      end

      File.rm(path)
    end
  rescue
    _ -> :ok
  end
end
