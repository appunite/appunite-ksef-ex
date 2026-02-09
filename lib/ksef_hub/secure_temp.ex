defmodule KsefHub.SecureTemp do
  @moduledoc """
  Secure temporary file utilities.

  Writes files with `0600` permissions and securely deletes them
  by overwriting contents with zeros before removal.
  """

  @doc """
  Writes content to a temporary file with `0600` permissions.

  Returns the absolute path to the created file.
  """
  @spec write(binary(), String.t()) :: String.t()
  def write(content, suffix) do
    path = path(suffix)
    File.write!(path, content)
    File.chmod!(path, 0o600)
    path
  end

  @doc """
  Generates a random temporary file path with the given suffix.

  Does not create the file.
  """
  @spec path(String.t()) :: String.t()
  def path(suffix) do
    random = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    Path.join(System.tmp_dir!(), "ksef_#{random}_#{suffix}")
  end

  @doc """
  Securely deletes a file by overwriting its contents with zeros before removal.

  No-op if the file does not exist.
  """
  @spec delete(String.t()) :: :ok
  def delete(path) do
    if File.exists?(path) do
      case File.stat(path) do
        {:ok, %{size: size}} when size > 0 ->
          File.write(path, :binary.copy(<<0>>, size))

        _ ->
          :ok
      end

      File.rm(path)
    end

    :ok
  rescue
    _ -> :ok
  end
end
