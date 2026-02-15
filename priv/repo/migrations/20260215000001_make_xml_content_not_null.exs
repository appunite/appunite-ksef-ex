defmodule KsefHub.Repo.Migrations.MakeXmlContentNotNull do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      modify :xml_content, :text, null: false, from: {:text, null: true}
    end
  end
end
