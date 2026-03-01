defmodule KsefHub.InboundEmail do
  @moduledoc """
  The InboundEmail context. Manages inbound email records for audit trail,
  idempotency, and PDF staging during async processing.
  """

  alias KsefHub.Files
  alias KsefHub.InboundEmail.InboundEmail, as: InboundEmailRecord
  alias KsefHub.Repo

  @doc "Creates an inbound email record for a company."
  @spec create_inbound_email(Ecto.UUID.t(), map()) ::
          {:ok, InboundEmailRecord.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_inbound_email(company_id, attrs) do
    {pdf_content, attrs} = Map.pop(attrs, :pdf_content)

    Repo.transaction(fn ->
      attrs =
        case pdf_content do
          nil ->
            attrs

          content ->
            case Files.create_file(%{
                   content: content,
                   content_type: "application/pdf",
                   filename: attrs[:original_filename]
                 }) do
              {:ok, file} ->
                Map.put(attrs, :pdf_file_id, file.id)

              {:error, reason} ->
                Repo.rollback(reason)
            end
        end

      case %InboundEmailRecord{}
           |> Ecto.Changeset.change(%{company_id: company_id})
           |> InboundEmailRecord.changeset(attrs)
           |> Repo.insert() do
        {:ok, record} -> record
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Fetches an inbound email by ID."
  @spec get_inbound_email(Ecto.UUID.t()) :: InboundEmailRecord.t() | nil
  def get_inbound_email(id) do
    InboundEmailRecord
    |> Repo.get(id)
    |> maybe_preload_pdf_file()
  end

  @doc "Fetches an inbound email by ID, raising if not found."
  @spec get_inbound_email!(Ecto.UUID.t()) :: InboundEmailRecord.t()
  def get_inbound_email!(id) do
    InboundEmailRecord
    |> Repo.get!(id)
    |> Repo.preload(:pdf_file)
  end

  @doc "Updates the status of an inbound email record."
  @spec update_status(InboundEmailRecord.t(), map()) ::
          {:ok, InboundEmailRecord.t()} | {:error, Ecto.Changeset.t()}
  def update_status(%InboundEmailRecord{} = record, attrs) do
    record
    |> InboundEmailRecord.status_changeset(attrs)
    |> Repo.update()
  end

  @spec maybe_preload_pdf_file(InboundEmailRecord.t() | nil) :: InboundEmailRecord.t() | nil
  defp maybe_preload_pdf_file(nil), do: nil
  defp maybe_preload_pdf_file(record), do: Repo.preload(record, :pdf_file)
end
