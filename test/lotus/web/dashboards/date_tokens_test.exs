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

  describe "presets/1" do
    test "gives each token as a Koyomi preset whose key is the token" do
      for filter_type <- [:date, :date_range] do
        keys = filter_type |> DateTokens.presets() |> Enum.map(&Koyomi.Presets.key/1)
        assert keys == DateTokens.tokens(filter_type)
      end
    end

    test "covers the days core resolves the token to" do
      today = ~D[2026-09-16]

      for token <- DateToken.tokens() do
        {:ok, range} = Koyomi.Presets.to_range(token, today: today, first_day: 1)
        {:ok, core} = DateToken.range(token, today)
        assert {range.first, range.last} == {core.first, core.last}, token
      end
    end

    test "other filter types have no preset" do
      assert DateTokens.presets(:text) == []
    end
  end
end
