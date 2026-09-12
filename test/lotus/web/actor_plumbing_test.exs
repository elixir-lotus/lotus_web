defmodule Lotus.Web.ActorPlumbingTest do
  @moduledoc """
  The dashboard must hand Lotus core an actor for UI-driven calls. Without it
  an access-control plug sees `nil` for everything a user does in the browser.
  """

  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  defmodule RecorderPlug do
    def init(opts), do: opts

    def call(payload, _opts) do
      send(recipient(), {:middleware, Map.take(payload, [:context, :scope, :table_name])})
      {:cont, payload}
    end

    def watch, do: :persistent_term.put({__MODULE__, :recipient}, self())

    defp recipient, do: :persistent_term.get({__MODULE__, :recipient})
  end

  setup do
    previous = Application.get_env(:lotus, :middleware)

    Application.put_env(:lotus, :middleware, %{
      before_query: [{RecorderPlug, []}],
      after_list_schemas: [{RecorderPlug, []}],
      after_list_tables: [{RecorderPlug, []}],
      after_describe_table: [{RecorderPlug, []}]
    })

    Lotus.Config.reload!()
    Lotus.Middleware.compile(Lotus.Config.middleware())
    RecorderPlug.watch()

    on_exit(fn ->
      if previous do
        Application.put_env(:lotus, :middleware, previous)
      else
        Application.delete_env(:lotus, :middleware)
      end

      Lotus.Config.reload!()
      Lotus.Middleware.compile(Lotus.Config.middleware())
    end)

    :ok
  end

  # Every payload recorded so far. The dashboard must carry the actor on all of
  # them, not only on the ones a page makes directly.
  defp drain_middleware(acc \\ []) do
    receive do
      {:middleware, payload} -> drain_middleware([payload | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp await_middleware(key) do
    receive do
      {:middleware, %{^key => _} = payload} -> payload
    after
      2_000 -> flunk("no middleware payload carrying #{inspect(key)} arrived")
    end
  end

  describe "a dashboard whose resolver builds an actor" do
    test "passes context and scope into a query run from the editor" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Actor Query",
          statement: "SELECT name FROM test_users ORDER BY name"
        })

      {:ok, live, _html} = live(build_conn(), "/scoped/queries/#{query.id}")
      render_async(live)

      assert %{context: %{user_id: 42}, scope: %{tenant_id: "acme"}} = await_middleware(:context)
    end

    test "passes context and scope into schema discovery" do
      {:ok, live, _html} = live(build_conn(), "/scoped/queries/new")
      render_async(live)

      assert %{context: %{user_id: 42}, scope: %{tenant_id: "acme"}} = await_middleware(:scope)
    end

    # A LiveComponent holds only what its parent passes, so a component that
    # calls core needs the actor handed down. Assert on every discovery call the
    # editor makes, not only the ones the page makes itself.
    test "every discovery call the query editor makes carries the actor" do
      {:ok, live, _html} = live(build_conn(), "/scoped/queries/new")
      render_async(live)

      payloads = drain_middleware()

      assert payloads != [], "no discovery call reached the middleware"

      for payload <- payloads do
        assert payload.context == %{user_id: 42}
        assert payload.scope == %{tenant_id: "acme"}
      end
    end

    # `describe_table/3` runs only from the schema explorer, so a payload for it
    # proves the actor reached that component rather than the page.
    test "passes the actor into describe_table from the schema explorer" do
      {:ok, live, _html} = live(build_conn(), "/scoped/queries/new")
      render_async(live)

      live |> element("[phx-click='toggle_schema_explorer']") |> render_click()

      live
      |> element("[phx-click='select_table'][phx-value-table='test_users']")
      |> render_click()

      payload = await_middleware(:table_name)

      assert payload.context == %{user_id: 42}
      assert payload.scope == %{tenant_id: "acme"}
    end
  end

  describe "a dashboard mounted without a resolver" do
    test "runs a query with no actor at all" do
      create_test_users()

      query =
        query_fixture(%{
          name: "Unscoped Query",
          statement: "SELECT name FROM test_users ORDER BY name"
        })

      {:ok, live, _html} = live(build_conn(), "/lotus/queries/#{query.id}")
      render_async(live)

      assert %{context: nil, scope: nil} = await_middleware(:context)
    end
  end
end
