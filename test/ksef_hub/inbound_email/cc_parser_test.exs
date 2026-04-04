defmodule KsefHub.InboundEmail.CcParserTest do
  use ExUnit.Case, async: true

  alias KsefHub.InboundEmail.CcParser

  describe "parse_cc_header/1" do
    test "returns empty list for nil" do
      assert CcParser.parse_cc_header(nil) == []
    end

    test "returns empty list for empty string" do
      assert CcParser.parse_cc_header("") == []
    end

    test "parses bare email address" do
      assert CcParser.parse_cc_header("alice@example.com") == [
               {"alice@example.com", "alice@example.com"}
             ]
    end

    test "parses email with display name" do
      assert CcParser.parse_cc_header("Alice Smith <alice@example.com>") == [
               {"Alice Smith", "alice@example.com"}
             ]
    end

    test "parses quoted display name" do
      assert CcParser.parse_cc_header("\"Alice Smith\" <alice@example.com>") == [
               {"Alice Smith", "alice@example.com"}
             ]
    end

    test "parses angle-bracketed email without display name" do
      assert CcParser.parse_cc_header("<alice@example.com>") == [
               {"alice@example.com", "alice@example.com"}
             ]
    end

    test "parses multiple comma-separated addresses" do
      header = "Alice <alice@example.com>, bob@example.com, Charlie <charlie@example.com>"

      assert CcParser.parse_cc_header(header) == [
               {"Alice", "alice@example.com"},
               {"bob@example.com", "bob@example.com"},
               {"Charlie", "charlie@example.com"}
             ]
    end

    test "handles extra whitespace" do
      header = "  alice@example.com ,  Bob  <bob@example.com>  "

      assert CcParser.parse_cc_header(header) == [
               {"alice@example.com", "alice@example.com"},
               {"Bob", "bob@example.com"}
             ]
    end

    test "skips empty segments between commas" do
      header = "alice@example.com,,bob@example.com"

      assert CcParser.parse_cc_header(header) == [
               {"alice@example.com", "alice@example.com"},
               {"bob@example.com", "bob@example.com"}
             ]
    end

    test "skips entries without @ sign" do
      header = "alice@example.com, not-an-email, bob@example.com"

      assert CcParser.parse_cc_header(header) == [
               {"alice@example.com", "alice@example.com"},
               {"bob@example.com", "bob@example.com"}
             ]
    end
  end

  describe "build_cc_list/3" do
    test "merges original CC and company CC" do
      result = CcParser.build_cc_list("team@co.com", "boss@co.com", [])

      assert result == [
               {"team@co.com", "team@co.com"},
               {"boss@co.com", "boss@co.com"}
             ]
    end

    test "deduplicates by email (case-insensitive)" do
      result = CcParser.build_cc_list("Alice <alice@co.com>", "alice@co.com", [])
      assert result == [{"Alice", "alice@co.com"}]
    end

    test "excludes sender address" do
      result =
        CcParser.build_cc_list(
          "sender@co.com, team@co.com",
          nil,
          ["sender@co.com"]
        )

      assert result == [{"team@co.com", "team@co.com"}]
    end

    test "excludes inbound recipient address" do
      result =
        CcParser.build_cc_list(
          "inv-abc123@inbound.ksef.com, team@co.com",
          nil,
          ["inv-abc123@inbound.ksef.com"]
        )

      assert result == [{"team@co.com", "team@co.com"}]
    end

    test "exclusion is case-insensitive" do
      result =
        CcParser.build_cc_list(
          "Sender@CO.com, team@co.com",
          nil,
          ["sender@co.com"]
        )

      assert result == [{"team@co.com", "team@co.com"}]
    end

    test "returns empty list when all addresses are excluded" do
      result = CcParser.build_cc_list("sender@co.com", nil, ["sender@co.com"])
      assert result == []
    end

    test "handles nil original CC with company CC" do
      result = CcParser.build_cc_list(nil, "boss@co.com", [])
      assert result == [{"boss@co.com", "boss@co.com"}]
    end

    test "handles original CC with nil company CC" do
      result = CcParser.build_cc_list("team@co.com", nil, [])
      assert result == [{"team@co.com", "team@co.com"}]
    end

    test "handles both nil" do
      assert CcParser.build_cc_list(nil, nil, []) == []
    end

    test "handles both empty" do
      assert CcParser.build_cc_list("", "", []) == []
    end

    test "preserves display names from original CC" do
      result = CcParser.build_cc_list("Alice Smith <alice@co.com>", nil, [])
      assert result == [{"Alice Smith", "alice@co.com"}]
    end
  end
end
