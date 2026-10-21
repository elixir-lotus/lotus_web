defmodule Lotus.Web.MCP.SetupTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lotus.Web.MCP.Setup

  setup do
    lotus = Application.fetch_env(:lotus, :mcp)
    lotus_web = Application.fetch_env(:lotus_web, Lotus.Web.MCP)
    Application.delete_env(:lotus, :mcp)
    Application.delete_env(:lotus_web, Lotus.Web.MCP)

    on_exit(fn ->
      restore(:lotus, :mcp, lotus)
      restore(:lotus_web, Lotus.Web.MCP, lotus_web)
    end)
  end

  defp restore(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore(app, key, :error), do: Application.delete_env(app, key)

  describe "with Sake" do
    test "a resolver for Lotus.Web.MCP defaults Lotus's authorize and actor to it" do
      Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)

      assert :ok = Setup.run(true)

      assert Application.get_env(:lotus, :mcp) == [
               authorize: {Lotus.Web.MCP, :authorize?},
               actor: {Lotus.Web.MCP, :actor}
             ]
    end

    test "keeps what the host set, and its other keys" do
      Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)
      Application.put_env(:lotus, :mcp, authorize: {MyApp, :mcp?}, data_sources: ["main"])

      Setup.run(true)

      mcp = Application.get_env(:lotus, :mcp)
      assert mcp[:authorize] == {MyApp, :mcp?}
      assert mcp[:actor] == {Lotus.Web.MCP, :actor}
      assert mcp[:data_sources] == ["main"]
    end

    test "without a resolver, Lotus's config is left alone" do
      Setup.run(true)
      assert Application.fetch_env(:lotus, :mcp) == :error
    end

    test "says nothing" do
      Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)
      assert capture_log(fn -> Setup.run(true) end) == ""
    end
  end

  describe "without Sake" do
    test "warns when MCP is configured" do
      Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)
      Application.put_env(:lotus, :mcp, authorize: {MyApp, :mcp?})

      log = capture_log(fn -> Setup.run(false) end)

      assert log =~ "config :lotus, :mcp and config :lotus_web, Lotus.Web.MCP are set"
      assert log =~ ~s(Add {:sake, "~> 0.4"})
    end

    test "names the one setting that is configured" do
      Application.put_env(:lotus, :mcp, authorize: {MyApp, :mcp?})

      assert capture_log(fn -> Setup.run(false) end) =~ "config :lotus, :mcp is set"
    end

    test "does not default Lotus's config" do
      Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)
      capture_log(fn -> Setup.run(false) end)

      assert Application.fetch_env(:lotus, :mcp) == :error
    end

    test "says nothing when MCP is not configured" do
      assert capture_log(fn -> Setup.run(false) end) == ""
    end
  end
end
