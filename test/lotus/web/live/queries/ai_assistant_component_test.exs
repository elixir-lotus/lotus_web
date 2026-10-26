defmodule Lotus.Web.Queries.AiAssistantComponentTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Queries.AiAssistantComponent, as: Assistant

  describe "diff/2" do
    test "marks the lines a refinement adds and removes" do
      base = "SELECT *\nFROM orders\nORDER BY 1"
      statement = "SELECT *\nFROM orders\nWHERE status = 'completed'\nORDER BY 2"

      assert Assistant.diff(base, statement) == [
               {:eq, "SELECT *"},
               {:eq, "FROM orders"},
               {:del, "ORDER BY 1"},
               {:ins, "WHERE status = 'completed'"},
               {:ins, "ORDER BY 2"}
             ]
    end

    test "is nil with nothing in the editor, the same query, or a new one" do
      assert Assistant.diff(nil, "SELECT 1") == nil
      assert Assistant.diff("  ", "SELECT 1") == nil
      assert Assistant.diff("SELECT 1\n", "SELECT 1") == nil
      assert Assistant.diff("SELECT 1", "SELECT 2") == nil
    end
  end

  describe "suggested_prompts/1" do
    test "are made of the source's tables and columns" do
      schema = %{
        "orders" => ~w(id status total_amount user_id inserted_at),
        "users" => ~w(id name email status inserted_at)
      }

      assert Assistant.suggested_prompts(schema) == [
               "Total amount by month in orders",
               "How many orders are there by status?",
               "The 10 most recent orders"
             ]
    end

    test "take a table whose columns are not described yet for one without" do
      schema = %{"orders" => ~w(id status inserted_at), "users" => nil}

      assert Assistant.suggested_prompts(schema) == [
               "How many orders are there by status?",
               "The 10 most recent orders",
               "Which tables have the most rows?"
             ]
    end

    test "fall back to examples without a schema" do
      assert length(Assistant.suggested_prompts(nil)) == 3
      assert length(Assistant.suggested_prompts(%{})) == 3
    end
  end

  test "suggestion_parts/1 sets a suggestion's statements apart" do
    text = "An index helps.\n\nCREATE INDEX a ON orders (status);\n\nThen analyze."

    assert Assistant.suggestion_parts(text) == [
             {:text, "An index helps."},
             {:sql, "CREATE INDEX a ON orders (status);"},
             {:text, "Then analyze."}
           ]
  end
end
