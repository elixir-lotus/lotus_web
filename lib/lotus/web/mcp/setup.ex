defmodule Lotus.Web.MCP.Setup do
  @moduledoc false
  # Run when Lotus Web starts. Compiled with or without Sake, so it can say
  # when Sake is missing: without it `Lotus.Web.MCP` is not compiled, and a
  # host that configured it is warned rather than left with a module that
  # silently does not exist. Lotus warns about `config :lotus, :mcp` itself.

  require Logger

  @spec run(boolean()) :: :ok
  def run(sake? \\ Code.ensure_loaded?(Sake.Server)) do
    if not sake? and Application.get_env(:lotus_web, Lotus.Web.MCP) != nil do
      Logger.warning(
        "config :lotus_web, Lotus.Web.MCP is set, but Sake is not a dependency, so " <>
          "Lotus.Web.MCP is not compiled. Add {:sake, \"~> 0.4\"} to your deps and recompile " <>
          "lotus and lotus_web (mix deps.compile lotus lotus_web --force) to serve MCP."
      )
    end

    :ok
  end
end
