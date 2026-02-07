defmodule KsefHub.Pdf.Xsltproc do
  @moduledoc """
  Wraps xsltproc CLI to transform FA(3) XML into HTML using gov.pl stylesheets.
  Uses secure temp files with 0600 permissions in a private per-run directory, cleaned up after use.
  """

  require Logger

  @cmd_timeout 30_000

  @doc """
  Transforms FA(3) XML content into HTML using the gov.pl XSL stylesheet.
  Returns `{:ok, html}` or `{:error, reason}`.
  """
  @spec transform(String.t()) :: {:ok, String.t()} | {:error, term()}
  def transform(xml_content) when is_binary(xml_content) do
    xsl_path = xsl_path()

    if File.exists?(xsl_path) do
      do_transform(xml_content, xsl_path)
    else
      {:error, :xsl_not_found}
    end
  end

  defp do_transform(xml_content, xsl_path) do
    run_dir = create_run_dir!()

    try do
      xml_path = write_secure_temp(run_dir, xml_content, "invoice.xml")

      task = Task.async(fn ->
        System.cmd("xsltproc", ["--nonet", xsl_path, xml_path],
          stderr_to_stdout: true
        )
      end)

      case Task.yield(task, @cmd_timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {output, 0}} ->
          {:ok, output}

        {:ok, {output, exit_code}} ->
          Logger.error("xsltproc failed (exit #{exit_code}, output: #{byte_size(output)} bytes)")
          {:error, {:xsltproc_failed, exit_code, output}}

        nil ->
          Logger.error("xsltproc timed out after #{@cmd_timeout}ms")
          {:error, :xsltproc_timeout}
      end
    rescue
      e in ErlangError ->
        Logger.error("xsltproc not available: #{Exception.message(e)}")
        {:error, :xsltproc_not_available}
    after
      secure_delete_dir(run_dir)
    end
  end

  defp xsl_path do
    default = Path.join(:code.priv_dir(:ksef_hub), "xsl/fa3-styl.xsl")
    Application.get_env(:ksef_hub, :xsl_path, default)
  end

  defp create_run_dir! do
    random = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    dir = Path.join(System.tmp_dir!(), "ksef_pdf_#{random}")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    dir
  end

  defp write_secure_temp(dir, content, filename) do
    path = Path.join(dir, filename)
    File.touch!(path)
    File.chmod!(path, 0o600)
    File.write!(path, content)
    path
  end

  defp secure_delete_dir(dir) do
    if File.exists?(dir) do
      dir
      |> File.ls!()
      |> Enum.each(fn file ->
        path = Path.join(dir, file)

        case File.stat(path) do
          {:ok, %{size: size}} when size > 0 ->
            File.write(path, :binary.copy(<<0>>, size))

          _ ->
            :ok
        end

        File.rm(path)
      end)

      File.rmdir(dir)
    end
  rescue
    _ -> :ok
  end
end
