defmodule Lotus.Web.Dashboards.DateTokensTest do
  use ExUnit.Case, async: true

  alias Lotus.Dashboards.DateToken
  alias Lotus.Web.Dashboards.DateTokens

  describe "groups/1" do
    test "a date range filter offers every core token" do
      assert Enum.sort(DateTokens.tokens(:date_range)) == Enum.sort(DateToken.tokens())
    end

    test "a date filter offers only the single-day tokens" do
      assert DateTokens.tokens(:date) == ["today", "yesterday"]
    end

    test "other filter types offer no token" do
      assert DateTokens.groups(:text) == []
      assert DateTokens.groups(:select) == []
    end
  end

  test "every token has a label that is not the token" do
    for token <- DateToken.tokens() do
      refute DateTokens.label(token) == token
    end

    assert DateTokens.label("last_30_days") == "Last 30 days"
  end

  describe "describe/2" do
    test "shows the dates a range token covers, with the year once" do
      assert DateTokens.describe("last_30_days", ~D[2026-09-15]) == "Aug 17 – Sep 15, 2026"
      assert DateTokens.describe("last_year", ~D[2026-09-15]) == "Jan 1 – Dec 31, 2025"
    end

    test "shows both years when the range crosses a year" do
      assert DateTokens.describe("last_90_days", ~D[2026-01-10]) == "Oct 13, 2025 – Jan 10, 2026"
    end

    test "shows one date for a single-day token" do
      assert DateTokens.describe("today", ~D[2026-09-15]) == "Sep 15, 2026"
    end

    test "is nil for a value that is not a token" do
      assert DateTokens.describe("2026-09-15", ~D[2026-09-15]) == nil
    end
  end
end
