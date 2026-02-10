defmodule KsefHub.Credentials.UserCertificateTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Credentials.UserCertificate

  describe "changeset/2" do
    test "valid with required fields" do
      user = insert(:user)

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(%{
          certificate_data_encrypted: "encrypted-data",
          certificate_password_encrypted: "encrypted-pass",
          is_active: true
        })

      assert changeset.valid?
    end

    test "requires certificate_data_encrypted" do
      user = insert(:user)

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(%{
          certificate_password_encrypted: "encrypted-pass"
        })

      assert %{certificate_data_encrypted: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires certificate_password_encrypted" do
      user = insert(:user)

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(%{
          certificate_data_encrypted: "encrypted-data"
        })

      assert %{certificate_password_encrypted: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires user_id" do
      changeset =
        %UserCertificate{}
        |> UserCertificate.changeset(%{
          certificate_data_encrypted: "encrypted-data",
          certificate_password_encrypted: "encrypted-pass"
        })

      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts optional fields" do
      user = insert(:user)

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(%{
          certificate_data_encrypted: "encrypted-data",
          certificate_password_encrypted: "encrypted-pass",
          certificate_subject: "CN=Jan Kowalski, PESEL=12345678901",
          not_before: ~D[2026-01-01],
          not_after: ~D[2028-01-01],
          fingerprint: "AA:BB:CC:DD",
          is_active: true
        })

      assert changeset.valid?
    end

    test "enforces unique active certificate per user" do
      user = insert(:user)
      insert(:user_certificate, user: user, is_active: true)

      assert {:error, changeset} =
               %UserCertificate{user_id: user.id}
               |> UserCertificate.changeset(%{
                 certificate_data_encrypted: "other-data",
                 certificate_password_encrypted: "other-pass",
                 is_active: true
               })
               |> Repo.insert()

      assert %{user_id: ["already has an active certificate"]} = errors_on(changeset)
    end

    test "allows multiple inactive certificates per user" do
      user = insert(:user)
      insert(:user_certificate, user: user, is_active: false)

      assert {:ok, _} =
               %UserCertificate{user_id: user.id}
               |> UserCertificate.changeset(%{
                 certificate_data_encrypted: "other-data",
                 certificate_password_encrypted: "other-pass",
                 is_active: false
               })
               |> Repo.insert()
    end

    test "allows new active certificate when existing is inactive" do
      user = insert(:user)
      insert(:user_certificate, user: user, is_active: false)

      assert {:ok, _} =
               %UserCertificate{user_id: user.id}
               |> UserCertificate.changeset(%{
                 certificate_data_encrypted: "new-data",
                 certificate_password_encrypted: "new-pass",
                 is_active: true
               })
               |> Repo.insert()
    end

    test "does not cast user_id from attrs" do
      user = insert(:user)
      other_user = insert(:user)

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(%{
          certificate_data_encrypted: "data",
          certificate_password_encrypted: "pass",
          user_id: other_user.id
        })

      # user_id should remain the struct value, not the attrs value
      assert Ecto.Changeset.get_field(changeset, :user_id) == user.id
    end
  end
end
