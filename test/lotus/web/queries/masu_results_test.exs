defmodule Lotus.Web.Queries.MasuResultsTest do
  use ExUnit.Case, async: true

  alias Lotus.Query.Filter
  alias Lotus.Query.Sort
  alias Lotus.Web.Queries.MasuResults

  defp query(filters, sorts \\ []), do: %Masu.Query{filters: filters, sorts: sorts}
  defp filter(key, op, value \\ nil), do: %Masu.Filter{key: key, op: op, value: value}

  describe "lotus_query/1" do
    test "the comparisons are Lotus's" do
      for op <- [:eq, :neq, :gt, :lt, :gte, :lte] do
        assert MasuResults.lotus_query(query([filter("n", op, 3)])) ==
                 {[Filter.new("n", op, 3)], []}
      end
    end

    test "between is two comparisons" do
      assert MasuResults.lotus_query(query([filter("n", :between, [1, 9])])) ==
               {[Filter.new("n", :gte, 1), Filter.new("n", :lte, 9)], []}
    end

    test "contains, starts with and ends with are LIKE" do
      {filters, []} =
        MasuResults.lotus_query(
          query([
            filter("s", :contains, "ab"),
            filter("s", :starts_with, "ab"),
            filter("s", :ends_with, "ab")
          ])
        )

      assert Enum.map(filters, &{&1.op, &1.value}) ==
               [{:like, "%ab%"}, {:like, "ab%"}, {:like, "%ab"}]
    end

    test "empty and not empty are null and not null" do
      assert MasuResults.lotus_query(query([filter("s", :is_nil), filter("s", :not_nil)])) ==
               {[Filter.new("s", :is_null), Filter.new("s", :is_not_null)], []}
    end

    test "Lotus runs one sort, the first" do
      sorts = [%Masu.Sort{key: "a", direction: :desc}, %Masu.Sort{key: "b", direction: :asc}]

      assert MasuResults.lotus_query(query([], sorts)) == {[], [Sort.new("a", :desc)]}
    end
  end
end
