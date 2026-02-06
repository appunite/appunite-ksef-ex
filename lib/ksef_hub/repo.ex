defmodule KsefHub.Repo do
  use Ecto.Repo,
    otp_app: :ksef_hub,
    adapter: Ecto.Adapters.Postgres
end
