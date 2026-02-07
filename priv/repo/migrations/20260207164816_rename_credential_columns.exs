defmodule KsefHub.Repo.Migrations.RenameCredentialColumns do
  use Ecto.Migration

  def change do
    rename table(:ksef_credentials), :certificate_data, to: :certificate_data_encrypted
    rename table(:ksef_credentials), :access_token, to: :access_token_encrypted
  end
end
