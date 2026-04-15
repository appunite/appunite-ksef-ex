defmodule KsefHub.Invoices.Comments do
  @moduledoc """
  Comment management for invoices.

  Provides CRUD operations for invoice comments with user ownership checks
  and activity-log event emission. Comments are scoped to a company via the
  parent invoice.

  This module is used internally by `KsefHub.Invoices` — the public API facade
  delegates to the functions here.
  """

  import Ecto.Query

  alias KsefHub.Accounts.User
  alias KsefHub.ActivityLog.Events
  alias KsefHub.Invoices.{Invoice, InvoiceComment}
  alias KsefHub.Repo

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Lists comments for an invoice, ordered by insertion time ascending, with user preloaded. Scoped to company."
  @spec list_invoice_comments(Ecto.UUID.t(), Ecto.UUID.t()) :: [InvoiceComment.t()]
  def list_invoice_comments(company_id, invoice_id) do
    InvoiceComment
    |> join(:inner, [c], i in Invoice, on: c.invoice_id == i.id)
    |> where([c, i], c.invoice_id == ^invoice_id and i.company_id == ^company_id)
    |> order_by([c], asc: c.inserted_at, asc: c.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Creates a comment on an invoice and returns it with user preloaded. Verifies invoice belongs to company."
  @spec create_invoice_comment(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), map(), keyword()) ::
          {:ok, InvoiceComment.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def create_invoice_comment(company_id, invoice_id, user_id, attrs, opts \\ []) do
    case Repo.get_by(Invoice, id: invoice_id, company_id: company_id) do
      nil ->
        {:error, :not_found}

      _invoice ->
        %InvoiceComment{}
        |> Ecto.Changeset.change(%{invoice_id: invoice_id, user_id: user_id})
        |> InvoiceComment.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, comment} ->
            comment = Repo.preload(comment, :user)
            invoice_ref = %{id: invoice_id, company_id: company_id}

            event_opts =
              opts
              |> Keyword.put_new(:user_id, user_id)
              |> Keyword.put_new_lazy(:actor_label, fn ->
                comment.user && (comment.user.name || comment.user.email)
              end)

            Events.invoice_comment_added(invoice_ref, comment, event_opts)
            {:ok, comment}

          error ->
            error
        end
    end
  end

  @doc "Updates an existing comment's body. Returns {:error, :unauthorized} if the user doesn't own the comment."
  @spec update_invoice_comment(InvoiceComment.t(), User.t(), map(), keyword()) ::
          {:ok, InvoiceComment.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def update_invoice_comment(%InvoiceComment{} = comment, %User{} = user, attrs, opts \\ []) do
    if comment.user_id != user.id do
      {:error, :unauthorized}
    else
      opts =
        opts
        |> Keyword.put_new(:user_id, user.id)
        |> Keyword.put_new(:actor_label, user.name || user.email)

      comment
      |> InvoiceComment.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          updated = Repo.preload(updated, :user)
          emit_comment_event(updated, "invoice.comment_edited", opts)
          {:ok, updated}

        error ->
          error
      end
    end
  end

  @doc "Deletes a comment. Returns {:error, :unauthorized} if the user doesn't own the comment."
  @spec delete_invoice_comment(InvoiceComment.t(), User.t(), keyword()) ::
          {:ok, InvoiceComment.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def delete_invoice_comment(%InvoiceComment{} = comment, %User{} = user, opts \\ []) do
    if comment.user_id != user.id do
      {:error, :unauthorized}
    else
      opts =
        opts
        |> Keyword.put_new(:user_id, user.id)
        |> Keyword.put_new(:actor_label, user.name || user.email)

      case Repo.delete(comment) do
        {:ok, deleted} ->
          emit_comment_event(deleted, "invoice.comment_deleted", opts)
          {:ok, deleted}

        error ->
          error
      end
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  @spec emit_comment_event(InvoiceComment.t(), String.t(), keyword()) :: :ok
  defp emit_comment_event(comment, action, opts) do
    # Look up company_id from the invoice for the event
    case Repo.get(Invoice, comment.invoice_id) do
      %Invoice{} = invoice ->
        case action do
          "invoice.comment_edited" ->
            Events.invoice_comment_edited(
              %{id: invoice.id, company_id: invoice.company_id},
              comment,
              opts
            )

          "invoice.comment_deleted" ->
            Events.invoice_comment_deleted(
              %{id: invoice.id, company_id: invoice.company_id},
              comment.id,
              opts
            )
        end

      nil ->
        :ok
    end
  end
end
