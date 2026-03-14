defmodule KsefHub.PaymentRequests.CsvDownload do
  @moduledoc "Tracks CSV download events for payment requests."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "payment_request_csv_downloads" do
    field :payment_request_ids, {:array, :binary_id}
    field :downloaded_at, :utc_datetime_usec

    belongs_to :user, KsefHub.Accounts.User
    belongs_to :company, KsefHub.Companies.Company
  end
end
