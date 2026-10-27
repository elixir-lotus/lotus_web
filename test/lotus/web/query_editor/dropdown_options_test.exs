defmodule Lotus.Web.QueryEditor.DropdownOptionsTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.QueryEditor.DropdownOptions

  describe "preview/2" do
    test "the first column is the value and the second the label" do
      preview =
        DropdownOptions.preview(%{
          columns: ["id", "name"],
          rows: [[1, "Alice"], [2, "Bob"]]
        })

      assert preview.options == [%{value: "1", label: "Alice"}, %{value: "2", label: "Bob"}]
      assert preview.value_column == "id"
      assert preview.label_column == "name"
      assert preview.count == 2
      refute preview.more?
      assert preview.warnings == []
    end

    test "one column is both the value and the label" do
      preview = DropdownOptions.preview(%{columns: ["status"], rows: [["open"]]})

      assert preview.options == [%{value: "open", label: "open"}]
      assert preview.label_column == "status"
    end

    test "rows past the limit are counted as more" do
      rows = Enum.map(1..4, &[&1])
      preview = DropdownOptions.preview(%{columns: ["n"], rows: rows}, 3)

      assert preview.count == 3
      assert preview.more?
    end

    test "warns of blank values, repeated values and columns left out" do
      preview =
        DropdownOptions.preview(%{
          columns: ["status", "label", "extra"],
          rows: [[nil, "None", 1], ["", "Empty", 2], ["a", "A", 3], ["a", "A", 4]]
        })

      assert preview.ignored_columns == ["extra"]

      assert [blank, repeated, ignored] = preview.warnings
      assert blank =~ "2 options have no value"
      assert repeated =~ "1 value comes more than once"
      assert ignored =~ "extra is left out"
    end

    test "no columns, no options" do
      assert %{options: [], count: 0} = DropdownOptions.preview(%{columns: [], rows: []})
    end
  end

  describe "column_sql/4" do
    test "lists each value once, labelled and sorted by the label" do
      assert DropdownOptions.column_sql("public", "users", "id", "name") ==
               ~s(SELECT DISTINCT "id" AS value, "name" AS label FROM "users" WHERE "id" IS NOT NULL ORDER BY label)
    end

    test "with no label, sorts by the value" do
      assert DropdownOptions.column_sql("public", "reporting.orders", "status", nil) ==
               ~s(SELECT DISTINCT "status" AS value FROM "reporting"."orders" WHERE "status" IS NOT NULL ORDER BY value)
    end
  end
end
