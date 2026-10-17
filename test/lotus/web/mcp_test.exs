defmodule Lotus.Web.MCPTest do
  use Lotus.Web.Case, async: false

  import Sake.Test, except: [connect: 2]

  @all ["lotus:read", "lotus:query", "lotus:write"]

  defmodule ActorResolver do
    @moduledoc false
    @behaviour Lotus.Web.Resolver

    def resolve_access(_user), do: :all
    def resolve_context(%{id: id}), do: %{user_id: id}
    def resolve_scope(_user), do: %{tenant_id: "acme"}
  end

  defmodule Recorder do
    @moduledoc false
    def init(pid), do: pid

    def call(payload, pid) do
      send(pid, {:before_query, payload.context})
      {:cont, payload}
    end
  end

  setup do
    create_test_users()

    Application.put_env(:lotus, :mcp,
      authorize: {Lotus.Web.MCP, :authorize?},
      actor: {Lotus.Web.MCP, :actor}
    )

    on_exit(fn ->
      Application.delete_env(:lotus, :mcp)
      Application.delete_env(:lotus_web, Lotus.Web.MCP)
    end)

    :ok
  end

  defp resolver(module), do: Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: module)

  defp client(opts \\ []),
    do: Sake.Test.connect(Lotus.Web.MCP, Keyword.merge([scope: %{id: 1}, scopes: @all], opts))

  defp names(client) do
    {:ok, tools} = list_tools(client)
    Enum.map(tools, & &1.name)
  end

  defp call!(client, tool, args) do
    {:ok, result} = call_tool(client, tool, args)
    result
  end

  describe "who may use it" do
    @tag :capture_log
    test "nobody without a resolver, or with one that does not resolve access" do
      assert names(client()) == []

      resolver(Lotus.Web.Test.ScopedResolver)
      assert names(client()) == []
    end

    test "whoever the resolver gives access, with every Lotus tool and show_chart" do
      resolver(Lotus.Web.Test.EditorResolver)
      names = names(client())

      for name <- ~w(list_data_sources run_sql run_query save_query save_chart show_chart),
          do: assert(name in names)
    end

    test "the dashboard's actor reaches Lotus" do
      resolver(ActorResolver)
      Lotus.Middleware.compile(%{before_query: [{Recorder, self()}]})
      on_exit(fn -> Lotus.Middleware.compile(%{}) end)

      call!(client(scope: %{id: 42}), "run_sql", %{
        "data_source" => "public",
        "statement" => "SELECT 1"
      })

      assert_receive {:before_query, %{user_id: 42}}
    end
  end

  describe "the resolver's decisions" do
    test "read-only access lists no write tool, and refuses one" do
      resolver(Lotus.Web.Test.ReadOnlyResolver)
      client = client()
      names = names(client)

      assert "run_sql" in names
      assert "show_chart" in names
      refute "save_query" in names
      refute "create_dashboard" in names

      assert {:error, {:rpc, _}} =
               call_tool(client, "create_dashboard", %{"name" => "Nope"})
    end

    test "authorize/3 refuses a source, and its lists leave it out" do
      resolver(Lotus.Web.Test.RestrictedResolver)
      client = client()

      assert %{is_error: true, text: "Restricted: query"} =
               call!(client, "run_sql", %{
                 "data_source" => "reporting",
                 "statement" => "SELECT 1"
               })

      assert %{is_error: false} =
               call!(client, "run_sql", %{"data_source" => "public", "statement" => "SELECT 1"})

      assert %{structured: %{"data_sources" => sources}, text: text} =
               call!(client, "list_data_sources", %{})

      assert Enum.map(sources, & &1["name"]) == ["public"]
      refute text =~ "reporting"

      query_fixture(%{name: "Public", data_source: "public"})
      query_fixture(%{name: "Reporting", data_source: "reporting"})

      assert %{structured: %{"queries" => [%{"name" => "Public"}]}} =
               call!(client, "list_queries", %{})
    end

    test "authorize/3 refuses an action that takes no resource, in the list too" do
      resolver(Lotus.Web.Test.RestrictedResolver)
      refute "save_query" in names(client())
    end

    test "authorize/3 refuses changing a query" do
      resolver(Lotus.Web.Test.AuthorResolver)
      query = query_fixture(%{statement: "SELECT name, age FROM test_users"})

      assert %{is_error: true, text: "Author: update_query"} =
               call!(client(), "update_query", %{"id" => query.id, "name" => "Renamed"})

      assert %{is_error: true, text: "Author: update_query"} =
               call!(client(), "save_chart", %{
                 "query_id" => query.id,
                 "chart_type" => "bar",
                 "x_field" => "name",
                 "y_field" => "age"
               })
    end
  end

  describe "show_chart" do
    setup do
      resolver(Lotus.Web.Test.EditorResolver)
      :ok
    end

    test "draws a statement as the chart asked for" do
      assert %{
               structured: %{
                 "chart" => %{"chart_type" => "bar", "x_field" => "name", "y_field" => "age"},
                 "spec" => %{"mark" => %{"type" => "bar"}, "data" => %{"values" => values}},
                 "num_rows" => 3,
                 "has_more" => false
               }
             } =
               call!(client(), "show_chart", %{
                 "data_source" => "public",
                 "statement" => "SELECT name, age FROM test_users ORDER BY name",
                 "chart_type" => "bar",
                 "x_field" => "name",
                 "y_field" => "age"
               })

      assert [%{"name" => "Alice", "age" => 30} | _] = values
    end

    test "draws a saved query with its own chart, and refuses one without" do
      query = query_fixture(%{name: "Ages", statement: "SELECT name, age FROM test_users"})
      client = client()

      assert %{is_error: true, text: "Give chart_type and its fields" <> _} =
               call!(client, "show_chart", %{"query_id" => query.id})

      {:ok, _} =
        Lotus.create_visualization(query, %{
          name: "Default",
          position: 0,
          config: %{"chart_type" => "line", "x_field" => "name", "y_field" => "age"}
        })

      assert %{structured: %{"title" => "Ages", "spec" => %{"mark" => %{"type" => "line"}}}} =
               call!(client, "show_chart", %{"query_id" => query.id})
    end

    test "refuses a field that is not a column, and a write" do
      client = client()

      assert %{is_error: true, text: "Not a column" <> _} =
               call!(client, "show_chart", %{
                 "data_source" => "public",
                 "statement" => "SELECT name FROM test_users",
                 "chart_type" => "bar",
                 "x_field" => "name",
                 "y_field" => "total"
               })

      assert %{is_error: true} =
               call!(client, "show_chart", %{
                 "data_source" => "public",
                 "statement" => "DELETE FROM test_users",
                 "chart_type" => "kpi",
                 "value_field" => "x"
               })

      assert %{rows: [[3]]} = TestRepo.query!("SELECT count(*) FROM test_users")
    end

    test "names its MCP App, a self-contained document" do
      client = client(ui: true)
      {:ok, tools} = list_tools(client)
      assert %{ui: "ui://lotus/chart"} = Enum.find(tools, &(&1.name == "show_chart"))

      assert {:ok, [%{text: html, mime_type: "text/html;profile=mcp-app"}]} =
               read_resource(client, "ui://lotus/chart")

      assert html =~ ~s(<div id="chart">)
      refute html =~ ~r/<script[^>]+src=/
    end
  end
end
