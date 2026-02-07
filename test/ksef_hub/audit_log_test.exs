defmodule KsefHub.AuditLogTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.AuditLog

  describe "log/2" do
    test "creates an audit log entry" do
      assert {:ok, %AuditLog{} = entry} = AuditLog.log("user.login")
      assert entry.action == "user.login"
    end

    test "creates entry with all options" do
      user = insert(:user)

      assert {:ok, entry} =
               AuditLog.log("cert.upload",
                 resource_type: "credential",
                 resource_id: "some-id",
                 metadata: %{"nip" => "1234567890"},
                 user_id: user.id,
                 ip_address: "127.0.0.1"
               )

      assert entry.action == "cert.upload"
      assert entry.resource_type == "credential"
      assert entry.user_id == user.id
      assert entry.ip_address == "127.0.0.1"
    end

    test "returns changeset error for invalid user_id" do
      assert {:error, changeset} =
               AuditLog.log("test.action", user_id: Ecto.UUID.generate())

      assert "does not exist" in errors_on(changeset).user_id
    end
  end

  describe "list_recent/1" do
    test "returns recent entries" do
      {:ok, _} = AuditLog.log("action.first")
      {:ok, _} = AuditLog.log("action.second")

      entries = AuditLog.list_recent()
      actions = Enum.map(entries, & &1.action)
      assert "action.first" in actions
      assert "action.second" in actions
    end

    test "respects limit" do
      for i <- 1..5, do: AuditLog.log("action.#{i}")

      assert length(AuditLog.list_recent(3)) == 3
    end

    test "clamps negative limit to default" do
      {:ok, _} = AuditLog.log("action.one")

      assert length(AuditLog.list_recent(-1)) == 1
    end

    test "clamps zero limit to default" do
      {:ok, _} = AuditLog.log("action.one")

      assert length(AuditLog.list_recent(0)) == 1
    end

    test "clamps huge limit to max" do
      {:ok, _} = AuditLog.log("action.one")

      # Should not crash, just returns available entries
      assert length(AuditLog.list_recent(999_999)) == 1
    end

    test "handles non-integer limit" do
      {:ok, _} = AuditLog.log("action.one")

      assert length(AuditLog.list_recent("bad")) == 1
    end
  end
end
