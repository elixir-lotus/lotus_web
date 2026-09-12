defmodule Lotus.Web.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lotus.Web.Router

  describe "__options__" do
    test "setting default options in the router module" do
      {session_name, session_opts, _public_session_opts, route_opts, export_opts} =
        Router.__options__("/lotus", [])

      assert session_name == :lotus_dashboard
      assert route_opts[:as] == :lotus_dashboard
      assert session_opts[:root_layout] == {Lotus.Web.Layouts, :root}
      assert export_opts[:private] == %{lotus_resolver: Lotus.Web.Resolver}
    end

    test "passing the transport through to the session" do
      assert %{"live_transport" => "longpoll"} = options_to_session(transport: "longpoll")
    end

    test "passing the live socket path through to the session" do
      assert %{"live_path" => "/alt"} = options_to_session(socket_path: "/alt")
    end

    test "passing csp nonce assign keys to the session" do
      assert %{"csp_nonces" => nonces} = options_to_session(csp_nonce_assign_key: nil)

      assert %{style: nil, script: nil} = nonces

      assert %{"csp_nonces" => %{style: "abc", script: "abc"}} =
               :get
               |> conn("/lotus")
               |> Plug.Conn.assign(:my_nonce, "abc")
               |> options_to_session(csp_nonce_assign_key: :my_nonce)
    end

    test "passing features through to the session" do
      assert %{"features" => []} = options_to_session([])

      assert %{"features" => [:timeout_options]} =
               options_to_session(features: [:timeout_options])
    end

    test "validating transport values" do
      assert_raise ArgumentError, ~r/invalid option for lotus_dashboard/, fn ->
        Router.__options__("/lotus", transport: "webpoll")
      end
    end
  end

  describe "resolver verification" do
    test "compiling a router with a resolver that does not exist fails the compile" do
      assert {:error, %ArgumentError{} = error} =
               compile_router("MissingResolverRouter", resolver: MyApp.NoSuchResolver)

      assert error.message =~ "MyApp.NoSuchResolver"
      assert error.message =~ ":resolver"
    end

    test "compiling a router with a resolver that exists succeeds" do
      assert :ok = compile_router("RealResolverRouter", resolver: Lotus.Web.Test.LazyResolver)
    end

    test "compiling a router without a resolver succeeds" do
      assert :ok = compile_router("DefaultResolverRouter", [])
    end
  end

  # The check runs in `@after_verify`, which the parallel checker calls from its
  # own process, so a raise there exits the caller instead of unwinding into
  # `assert_raise`. Compile in a monitored process and read the exit reason.
  defp compile_router(name, opts) do
    {result, _log} = ExUnit.CaptureLog.with_log(fn -> compile_in_task(name, opts) end)
    result
  end

  defp compile_in_task(name, opts) do
    call =
      case opts do
        [] -> ~s(lotus_dashboard "/lotus")
        opts -> ~s(lotus_dashboard "/lotus", #{inspect(opts)})
      end

    source = """
    defmodule Lotus.Web.RouterTest.#{name} do
      use Phoenix.Router

      import Lotus.Web.Router

      scope "/" do
        #{call}
      end
    end
    """

    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string(source)
          send(parent, :compiled)
        end)
      end)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        receive do
          :compiled -> :ok
        after
          0 -> {:error, :no_result}
        end

      {:DOWN, ^ref, :process, ^pid, {%{__exception__: true} = error, _stack}} ->
        {:error, error}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, reason}
    after
      10_000 -> {:error, :timeout}
    end
  end

  defp options_to_session(opts) do
    :get
    |> conn("/lotus")
    |> Plug.Test.init_test_session(%{})
    |> options_to_session(opts)
  end

  defp options_to_session(conn, opts) do
    {_name, sess_opts, _public_sess_opts, _opts, _export_opts} =
      Router.__options__("/lotus", opts)

    {Router, :__session__, session_opts} = Keyword.get(sess_opts, :session)

    apply(Router, :__session__, [conn | session_opts])
  end
end
