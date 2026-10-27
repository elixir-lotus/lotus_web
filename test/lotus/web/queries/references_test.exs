defmodule Lotus.Web.Queries.ReferencesTest do
  use Lotus.Web.Case

  alias Lotus.Query.Tokenizer.Profile
  alias Lotus.Web.Queries.References

  describe "single_table/2" do
    test "a plain select of one table" do
      assert References.single_table("SELECT * FROM test_posts") == {:ok, {nil, "test_posts"}}

      assert References.single_table("select id, user_id from public.test_posts where id > 1;") ==
               {:ok, {"public", "test_posts"}}

      assert References.single_table(
               ~s(SELECT p.title, p.user_id FROM "public"."test_posts" AS p ORDER BY p.id LIMIT 10)
             ) == {:ok, {"public", "test_posts"}}

      assert References.single_table("SELECT `a` FROM `t` WHERE x = {{x}} [[AND y = {{y}}]]") ==
               {:ok, {nil, "t"}}

      assert References.single_table("SELECT DISTINCT user_id FROM test_posts") ==
               {:ok, {nil, "test_posts"}}
    end

    test "not a statement whose columns may not be the table's" do
      for statement <- [
            "SELECT count(*) AS user_id FROM test_posts",
            "SELECT id + 1 AS user_id FROM test_posts",
            "SELECT user_id AS id FROM test_posts",
            "SELECT * FROM test_posts p JOIN test_users u ON u.id = p.user_id",
            "SELECT * FROM test_posts, test_users",
            "SELECT user_id FROM test_posts UNION SELECT id FROM test_users",
            "SELECT user_id FROM test_posts GROUP BY user_id",
            "SELECT * FROM (SELECT * FROM test_posts) p",
            "WITH p AS (SELECT * FROM test_posts) SELECT * FROM p",
            "SELECT u.id FROM test_posts p",
            "SELECT * FROM test_posts -- a comment",
            "SELECT * FROM test_posts; SELECT 1",
            "SELECT * FROM a.b.c",
            "UPDATE test_posts SET title = 'x'"
          ] do
        assert References.single_table(statement) == :error, statement
      end
    end

    test "a keyword, comment marker or semicolon in a literal or a quoted name" do
      assert References.single_table(
               "SELECT * FROM test_posts WHERE title = 'a -- b /* c */; d JOIN e UNION f'"
             ) == {:ok, {nil, "test_posts"}}

      assert References.single_table(~s(SELECT "group by", "union" FROM test_posts)) ==
               {:ok, {nil, "test_posts"}}

      assert References.single_table(
               "SELECT * FROM test_posts WHERE title = $$it's; -- here$$",
               Profile.for_language("sql:postgres")
             ) == {:ok, {nil, "test_posts"}}
    end

    test "the source's quotes" do
      mysql = Profile.for_language("sql:mysql")

      assert References.single_table(~s(SELECT * FROM `test posts` WHERE x = "a; b"), mysql) ==
               {:ok, {nil, "test posts"}}

      # In MySQL "user_id" is a string, so the column is a constant.
      assert References.single_table(~s(SELECT "user_id" FROM test_posts), mysql) == :error

      assert References.single_table("SELECT * FROM test_posts WHERE x = 1 # note", mysql) ==
               :error

      assert References.single_table("SELECT * FROM test_posts /*! UNION SELECT 1 */", mysql) ==
               :error
    end
  end

  describe "for_result/4" do
    test "the foreign key columns of a plain select, and the tables they reference" do
      assert References.for_result("public", "SELECT * FROM test_posts", [
               "id",
               "title",
               "user_id"
             ]) == %{
               "user_id" => %{schema: "public", table: "test_users", column: "id"}
             }
    end

    test "only the columns in the result" do
      assert References.for_result("public", "SELECT id, title FROM test_posts", ["id", "title"]) ==
               %{}
    end

    test "a schema-qualified table" do
      assert %{"customer_id" => %{schema: "reporting", table: "customers", column: "id"}} =
               References.for_result(
                 "reporting",
                 "SELECT id, customer_id FROM reporting.orders",
                 ["id", "customer_id"]
               )
    end

    test "none of a statement that is not plain, or of a table it cannot describe" do
      assert References.for_result("public", "SELECT user_id AS x FROM test_posts", ["x"]) == %{}
      assert References.for_result("public", "SELECT * FROM nowhere", ["user_id"]) == %{}
    end
  end

  describe "lookup/6" do
    test "a query of the row, the value bound to a variable" do
      assert {:ok, query, %{"id" => "42"}} =
               References.lookup("public", "public", "test_users", "id", "42")

      assert query.statement == ~s(SELECT * FROM "public"."test_users" WHERE "id" = {{id}})
      assert query.data_source == "public"
      assert [%{name: "id", type: :number, label: "id"}] = query.variables
    end

    test "nothing for a table or column the source does not describe" do
      assert References.lookup("public", "public", "nowhere", "id", "1") == :error
      assert References.lookup("public", "public", "test_users", "nope", "1") == :error

      assert References.lookup("public", "public", ~s(test_users" WHERE 1=1 --), "id", "1") ==
               :error
    end
  end
end
