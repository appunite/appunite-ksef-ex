# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     KsefHub.Repo.insert!(%KsefHub.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias KsefHub.Repo
alias KsefHub.ServiceConfig.ClassifierConfig

# Seed classifier configs for all companies that don't have one yet.
# Defaults: disabled, localhost URL, standard thresholds.
companies_without_config =
  from(c in KsefHub.Companies.Company,
    left_join: cc in ClassifierConfig,
    on: cc.company_id == c.id,
    where: is_nil(cc.id),
    select: c.id
  )
  |> Repo.all()

for company_id <- companies_without_config do
  %ClassifierConfig{company_id: company_id}
  |> Ecto.Changeset.change(%{
    enabled: false,
    url: ClassifierConfig.default_url(),
    category_confidence_threshold: ClassifierConfig.default_category_threshold(),
    tag_confidence_threshold: ClassifierConfig.default_tag_threshold()
  })
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :company_id)
end

if companies_without_config != [] do
  IO.puts("Seeded classifier config for #{length(companies_without_config)} company(ies)")
else
  IO.puts("All companies already have classifier configs")
end
