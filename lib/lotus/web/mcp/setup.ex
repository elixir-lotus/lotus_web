defmodule Lotus.Web.MCP.Setup do
  @moduledoc false
  # Run when Lotus Web starts. Compiled with or without Sake, so it can say
  # when Sake is missing.
  #
  # With Sake, and a resolver set for `Lotus.Web.MCP`, the `authorize` and
  # `actor` of `config :lotus, :mcp` can only be Lotus Web's own, so they
  # default to them: the host names its resolver once. Whatever the host
  # sets itself wins.
  #
  # Without Sake, `Lotus.MCP` and `Lotus.Web.MCP` are not compiled, so a host
  # that configured either is warned rather than left with a module that
  # silently does not exist.

  require Logger

  @defaults [authorize: {Lotus.Web.MCP, :authorize?}, actor: {Lotus.Web.MCP, :actor}]

  @spec run(boolean()) :: :ok
  def run(sake? \\ Code.ensure_loaded?(Lotus.Web.MCP)) do
    if sake?, do: default_lotus_config(), else: warn_if_configured()
    :ok
  end

  defp default_lotus_config do
    if Application.get_env(:lotus_web, Lotus.Web.MCP, [])[:resolver] do
      current = Application.get_env(:lotus, :mcp, [])
      Application.put_env(:lotus, :mcp, Keyword.merge(@defaults, current))
    end
  end

  defp warn_if_configured do
    configured =
      for {app, key, label} <- [
            {:lotus, :mcp, "config :lotus, :mcp"},
            {:lotus_web, Lotus.Web.MCP, "config :lotus_web, Lotus.Web.MCP"}
          ],
          Application.get_env(app, key) != nil,
          do: label

    if configured != [] do
      Logger.warning(
        "#{Enum.join(configured, " and ")} #{if length(configured) == 1, do: "is", else: "are"} " <>
          "set, but Sake is not a dependency, so Lotus.MCP and Lotus.Web.MCP are not compiled. " <>
          "Add {:sake, \"~> 0.4\"} to your deps and recompile lotus and lotus_web " <>
          "(mix deps.compile lotus lotus_web --force) to serve MCP."
      )
    end
  end
end
