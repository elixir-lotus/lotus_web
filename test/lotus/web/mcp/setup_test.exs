defmodule Lotus.Web.MCP.SetupTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lotus.Web.MCP.Setup

  setup do
    saved = Application.fetch_env(:lotus_web, Lotus.Web.MCP)

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:lotus_web, Lotus.Web.MCP, value)
        :error -> Application.delete_env(:lotus_web, Lotus.Web.MCP)
      end
    end)
  end

  test "warns when Lotus.Web.MCP is configured but Sake is missing" do
    Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)

    log = capture_log(fn -> assert :ok = Setup.run(false) end)

    assert log =~ "config :lotus_web, Lotus.Web.MCP is set, but Sake is not a dependency"
    assert log =~ ~s(Add {:sake, "~> 0.4"})
  end

  test "says nothing when it is not configured, or Sake is there" do
    Application.delete_env(:lotus_web, Lotus.Web.MCP)
    assert capture_log(fn -> Setup.run(false) end) == ""

    Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)
    assert capture_log(fn -> Setup.run(true) end) == ""
  end

  test "leaves Lotus's config alone" do
    lotus = Application.fetch_env(:lotus, :mcp)
    Application.put_env(:lotus_web, Lotus.Web.MCP, resolver: SomeResolver)

    Setup.run(true)
    capture_log(fn -> Setup.run(false) end)

    assert Application.fetch_env(:lotus, :mcp) == lotus
  end
end
