defmodule KsefHub.Repo.Migrations.RevertTokenDigestToToken do
  use Ecto.Migration

  def change do
    rename table(:invoice_public_tokens), :token_digest, to: :token
  end
end
