defmodule KsefHub.Credentials.UserCertificateTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Credentials.UserCertificate

  describe "changeset/2" do
    test "valid with required fields" do
      user = insert(:user)
      attrs = params_for(:user_certificate) |> Map.drop([:user_id])

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(attrs)

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
      attrs = params_for(:user_certificate) |> Map.drop([:user_id])

      changeset =
        %UserCertificate{}
        |> UserCertificate.changeset(attrs)

      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts optional fields" do
      user = insert(:user)

      attrs =
        params_for(:user_certificate)
        |> Map.drop([:user_id])
        |> Map.merge(%{
          certificate_subject: "CN=Jan Kowalski, PESEL=12345678901",
          not_before: ~D[2026-01-01],
          not_after: ~D[2028-01-01],
          fingerprint: "AA:BB:CC:DD"
        })

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(attrs)

      assert changeset.valid?
    end

    test "enforces unique active certificate per user" do
      user = insert(:user)
      insert(:user_certificate, user: user, is_active: true)

      attrs =
        params_for(:user_certificate)
        |> Map.drop([:user_id])

      assert {:error, changeset} =
               %UserCertificate{user_id: user.id}
               |> UserCertificate.changeset(attrs)
               |> Repo.insert()

      assert %{user_id: ["already has an active certificate"]} = errors_on(changeset)
    end

    test "allows multiple inactive certificates per user" do
      user = insert(:user)
      insert(:user_certificate, user: user, is_active: false)

      attrs =
        params_for(:user_certificate)
        |> Map.drop([:user_id])
        |> Map.put(:is_active, false)

      assert {:ok, _} =
               %UserCertificate{user_id: user.id}
               |> UserCertificate.changeset(attrs)
               |> Repo.insert()
    end

    test "allows new active certificate when existing is inactive" do
      user = insert(:user)
      insert(:user_certificate, user: user, is_active: false)

      attrs = params_for(:user_certificate) |> Map.drop([:user_id])

      assert {:ok, _} =
               %UserCertificate{user_id: user.id}
               |> UserCertificate.changeset(attrs)
               |> Repo.insert()
    end

    test "does not cast user_id from attrs" do
      user = insert(:user)
      other_user = insert(:user)

      attrs =
        params_for(:user_certificate)
        |> Map.drop([:user_id])
        |> Map.put(:user_id, other_user.id)

      changeset =
        %UserCertificate{user_id: user.id}
        |> UserCertificate.changeset(attrs)

      # user_id should remain the struct value, not the attrs value
      assert Ecto.Changeset.get_field(changeset, :user_id) == user.id
    end
  end
end
