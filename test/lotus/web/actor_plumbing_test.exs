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
      send(recipient(), {:middleware, Map.take(payload, [:context, :scope])})
      {:cont, payload}
    end

    def watch, do: :persistent_term.put({__MODULE__, :recipient}, self())

    defp recipient, do: :persistent_term.get({__MODULE__, :recipient})
  end

  setup do
    previous = Application.get_env(:lotus, :middleware)

    Application.put_env(:lotus, :middleware, %{
      before_query: [{RecorderPlug, []}],
      after_list_tables: [{RecorderPlug, []}]
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
