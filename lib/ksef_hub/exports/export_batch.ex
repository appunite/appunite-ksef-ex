defmodule KsefHub.Exports.ExportBatch do
  @moduledoc "Schema for export batch requests. Tracks status and result of bulk invoice exports."

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type status :: :pending | :processing | :completed | :failed

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_date_range_days 31

  schema "export_batches" do
    field :status, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed],
      default: :pending

    field :date_from, :date
    field :date_to, :date
    field :invoice_type, :string
    field :only_new, :boolean, default: false
    field :invoice_count, :integer
    field :error_message, :string

    belongs_to :user, KsefHub.Accounts.User
    belongs_to :company, KsefHub.Companies.Company
    belongs_to :zip_file, KsefHub.Files.File

    has_many :invoice_downloads, KsefHub.Exports.InvoiceDownload

    timestamps()
  end

  @doc "Builds a changeset for creating an export batch."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [:date_from, :date_to, :invoice_type, :only_new])
    |> validate_required([:date_from, :date_to])
    |> validate_invoice_type()
    |> validate_date_range()
  end

  @doc "Builds a changeset for updating export batch status and results."
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(batch, attrs) do
    batch
    |> cast(attrs, [:status, :invoice_count, :error_message, :zip_file_id])
  end

  @spec validate_invoice_type(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_invoice_type(changeset) do
    case get_field(changeset, :invoice_type) do
      nil -> changeset
      type when type in ["expense", "income"] -> changeset
      _ -> add_error(changeset, :invoice_type, "must be expense, income, or blank")
    end
  end

  @spec validate_date_range(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_date_range(changeset) do
    date_from = get_field(changeset, :date_from)
    date_to = get_field(changeset, :date_to)

    cond do
      is_nil(date_from) or is_nil(date_to) ->
        changeset

      Date.compare(date_to, date_from) == :lt ->
        add_error(changeset, :date_to, "must be on or after start date")

      Date.diff(date_to, date_from) >= @max_date_range_days ->
        add_error(changeset, :date_to, "date range cannot exceed #{@max_date_range_days} days")

      true ->
        changeset
    end
  end
end
