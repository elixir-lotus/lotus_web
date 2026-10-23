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

    test "contains, starts with and ends with are Lotus's, of text as written" do
      {filters, []} =
        MasuResults.lotus_query(
          query([
            filter("s", :contains, "ab"),
            filter("s", :starts_with, "ab"),
            filter("s", :ends_with, "ab")
          ])
        )

      assert Enum.map(filters, &{&1.op, &1.value}) ==
               [{:contains, "ab"}, {:starts_with, "ab"}, {:ends_with, "ab"}]
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

  describe "filters_for/1" do
    test "Masu's filters of the operators the source runs" do
      assert MasuResults.filters_for(Filter.operators()) ==
               ~w(eq neq gt lt gte lte contains starts_with ends_with is_nil not_nil)a

      assert MasuResults.filters_for(Filter.operators() -- Filter.text_operators()) ==
               ~w(eq neq gt lt gte lte is_nil not_nil)a

      assert MasuResults.filters_for([:eq, :like, :is_null]) == [:eq, :is_nil]
    end
  end

  describe "Masu's words" do
    alias Lotus.Web.Queries.MasuMessages

    # The same in French as in English.
    @same ["CSV", "Condition", "Excel (XLSX)", "Page", "Pages", "Total"]

    test "every word of Masu's grid, and only those" do
      assert Enum.sort(Map.keys(MasuMessages.messages())) ==
               Enum.sort(Map.keys(Masu.Messages.defaults()))
    end

    test "in French, none is left in English" do
      english = Masu.Messages.defaults()

      french = Gettext.with_locale(Lotus.Web.Gettext, "fr", &MasuMessages.messages/0)

      left =
        for {key, text} <- french, text == english[key], text not in @same, do: key

      assert left == []
    end

    test "a translation keeps Masu's placeholders" do
      french = Gettext.with_locale(Lotus.Web.Gettext, "fr", &MasuMessages.messages/0)

      for {key, text} <- Masu.Messages.defaults() do
        assert Regex.scan(~r/\{\w+\}/, french[key]) |> Enum.sort() ==
                 Regex.scan(~r/\{\w+\}/, text) |> Enum.sort(),
               "#{key}: #{french[key]}"
      end
    end
  end
end
