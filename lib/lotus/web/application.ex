defmodule Lotus.Web.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = Lotus.Web.MCP.Setup.run()

    children = []

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
