defmodule KsefHub.InboundEmail do
  @moduledoc """
  The InboundEmail context. Manages inbound email records for audit trail,
  idempotency, and PDF staging during async processing.
  """

  import Ecto.Query

  alias KsefHub.InboundEmail.InboundEmail, as: InboundEmailRecord
  alias KsefHub.Repo

  @doc "Creates an inbound email record for a company."
  @spec create_inbound_email(Ecto.UUID.t(), map()) ::
          {:ok, InboundEmailRecord.t()} | {:error, Ecto.Changeset.t()}
  def create_inbound_email(company_id, attrs) do
    %InboundEmailRecord{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> InboundEmailRecord.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Fetches an inbound email by ID."
  @spec get_inbound_email(Ecto.UUID.t()) :: InboundEmailRecord.t() | nil
  def get_inbound_email(id), do: Repo.get(InboundEmailRecord, id)

  @doc "Fetches an inbound email by ID, raising if not found."
  @spec get_inbound_email!(Ecto.UUID.t()) :: InboundEmailRecord.t()
  def get_inbound_email!(id), do: Repo.get!(InboundEmailRecord, id)

  @doc "Updates the status of an inbound email record."
  @spec update_status(InboundEmailRecord.t(), map()) ::
          {:ok, InboundEmailRecord.t()} | {:error, Ecto.Changeset.t()}
  def update_status(%InboundEmailRecord{} = record, attrs) do
    record
    |> InboundEmailRecord.status_changeset(attrs)
    |> Repo.update()
  end

  @doc "Checks if a Mailgun message has already been processed (idempotency)."
  @spec already_processed?(String.t()) :: boolean()
  def already_processed?(mailgun_message_id) when is_binary(mailgun_message_id) do
    InboundEmailRecord
    |> where([ie], ie.mailgun_message_id == ^mailgun_message_id)
    |> Repo.exists?()
  end
end
