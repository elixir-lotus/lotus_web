defmodule Lotus.Web.Case do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Lotus.Web.Case
      import Lotus.Web.Fixtures

      alias Lotus.Web.TestRepo
      alias Lotus.Web.Test.Router

      @endpoint Lotus.Web.Endpoint
    end
  end

  setup context do
    pid1 = Ecto.Adapters.SQL.Sandbox.start_owner!(Lotus.Web.TestRepo, shared: not context[:async])

    pid2 =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Lotus.Web.ReportingTestRepo,
        shared: not context[:async]
      )

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid1)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid2)
    end)

    :ok
  end

  @doc """
  The values of every table card on the page, as text: a table card is a
  Masu grid, whose rows the browser draws (`Masu.Test.rows/3`).
  """
  def table_values(live) do
    ~r/id="(table-\d+)"/
    |> Regex.scan(Phoenix.LiveViewTest.render(live), capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&Masu.Test.rows(live, &1))
    |> Enum.flat_map(&Map.values/1)
    |> Enum.map(&to_string/1)
  end
end
