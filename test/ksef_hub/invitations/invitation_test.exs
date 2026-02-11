defmodule KsefHub.Invitations.InvitationTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invitations.Invitation

  describe "changeset/2" do
    test "valid changeset with required fields" do
      company = insert(:company)
      user = insert(:user)

      invitation = %Invitation{
        company_id: company.id,
        invited_by_id: user.id,
        token_hash: "abc123hash",
        status: "pending",
        expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)
      }

      attrs = %{
        email: "invitee@example.com",
        role: "accountant"
      }

      changeset = Invitation.changeset(invitation, attrs)
      assert changeset.valid?
    end

    test "requires email, role, expires_at, company_id, invited_by_id, token_hash" do
      changeset = Invitation.changeset(%Invitation{}, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors[:email]
      assert "can't be blank" in errors[:role]
      assert "can't be blank" in errors[:expires_at]
      assert "can't be blank" in errors[:company_id]
      assert "can't be blank" in errors[:invited_by_id]
      assert "can't be blank" in errors[:token_hash]
    end

    test "validates role is accountant or invoice_reviewer" do
      changeset =
        %Invitation{
          company_id: Ecto.UUID.generate(),
          invited_by_id: Ecto.UUID.generate(),
          token_hash: "hash",
          status: "pending",
          expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)
        }
        |> Invitation.changeset(%{
          email: "test@example.com",
          role: "owner"
        })

      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "does not cast status or expires_at from attrs" do
      changeset =
        %Invitation{
          company_id: Ecto.UUID.generate(),
          invited_by_id: Ecto.UUID.generate(),
          token_hash: "hash",
          status: "pending",
          expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)
        }
        |> Invitation.changeset(%{
          email: "test@example.com",
          role: "accountant",
          status: "accepted",
          expires_at: DateTime.add(DateTime.utc_now(), -3600)
        })

      # Status and expires_at should remain as set on the struct
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"

      assert DateTime.diff(Ecto.Changeset.get_field(changeset, :expires_at), DateTime.utc_now()) >
               6 * 24 * 3600
    end

    test "validates email format" do
      changeset =
        %Invitation{
          company_id: Ecto.UUID.generate(),
          invited_by_id: Ecto.UUID.generate(),
          token_hash: "hash",
          status: "pending",
          expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)
        }
        |> Invitation.changeset(%{
          email: "not-an-email",
          role: "accountant"
        })

      assert %{email: ["must be a valid email address"]} = errors_on(changeset)
    end

    test "normalizes email to lowercase" do
      changeset =
        %Invitation{
          company_id: Ecto.UUID.generate(),
          invited_by_id: Ecto.UUID.generate(),
          token_hash: "hash",
          status: "pending",
          expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)
        }
        |> Invitation.changeset(%{
          email: "UPPER@Example.COM",
          role: "accountant"
        })

      assert Ecto.Changeset.get_change(changeset, :email) == "upper@example.com"
    end

    test "does not allow mass-assignment of company_id, invited_by_id, token_hash, status, or expires_at" do
      original_company = insert(:company)
      original_user = insert(:user)
      attacker_company = insert(:company)
      attacker_user = insert(:user)
      original_expires = DateTime.add(DateTime.utc_now(), 7 * 24 * 3600)

      invitation = %Invitation{
        company_id: original_company.id,
        invited_by_id: original_user.id,
        token_hash: "original-hash",
        status: "pending",
        expires_at: original_expires
      }

      # Attempt to overwrite protected fields via attrs
      changeset =
        Invitation.changeset(invitation, %{
          email: "test@example.com",
          role: "accountant",
          company_id: attacker_company.id,
          invited_by_id: attacker_user.id,
          token_hash: "attacker-hash",
          status: "accepted",
          expires_at: DateTime.add(DateTime.utc_now(), -3600)
        })

      # All protected fields should remain as set on the struct
      assert Ecto.Changeset.get_field(changeset, :company_id) == original_company.id
      assert Ecto.Changeset.get_field(changeset, :invited_by_id) == original_user.id
      assert Ecto.Changeset.get_field(changeset, :token_hash) == "original-hash"
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"
      assert Ecto.Changeset.get_field(changeset, :expires_at) == original_expires
    end

    test "enforces unique pending invitation per company+email" do
      company = insert(:company)
      user = insert(:user)

      insert(:invitation,
        company: company,
        invited_by: user,
        email: "dupe@example.com",
        status: "pending"
      )

      {:error, changeset} =
        %Invitation{
          company_id: company.id,
          invited_by_id: user.id,
          token_hash: "different-hash",
          status: "pending",
          expires_at:
            DateTime.add(DateTime.utc_now(), 7 * 24 * 3600) |> DateTime.truncate(:second)
        }
        |> Invitation.changeset(%{
          email: "dupe@example.com",
          role: "accountant"
        })
        |> Repo.insert()

      assert %{email: ["already has a pending invitation for this company"]} =
               errors_on(changeset)
    end
  end
end
