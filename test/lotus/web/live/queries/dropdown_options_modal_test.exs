defmodule Lotus.Web.Queries.DropdownOptionsModalTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Storage.QueryVariable
  alias Lotus.Web.Queries.DropdownOptionsModal

  setup do
    # As a page of the dashboard at /lotus stores it, for the link to a query.
    socket = %Phoenix.LiveView.Socket{endpoint: Lotus.Web.Endpoint, router: Lotus.Web.Test.Router}
    Process.put(:__lotus_web_prefix__, {socket, "/lotus"})
    :ok
  end

  defp render_modal(opts) do
    render_component(DropdownOptionsModal,
      id: "dropdown_options_modal",
      variable_name: "status",
      variable_data: Keyword.get(opts, :variable_data, %QueryVariable{name: "status"}),
      dynamic_options: Keyword.fetch!(opts, :dynamic_options),
      data_source: "public",
      search_path: Keyword.get(opts, :search_path),
      tables: ["orders"],
      saved_queries: Keyword.get(opts, :saved_queries, []),
      parent: nil
    )
  end

  describe "sources that can populate options from a query" do
    test "offers the custom list, a column, SQL and a saved query" do
      html = render_modal(dynamic_options: true)

      assert html =~ "Custom list"
      assert html =~ "Pick a column"
      assert html =~ "Write SQL"
      assert html =~ "Saved query"
    end

    test "opens on the SQL editor for a variable already populated from SQL" do
      variable = %QueryVariable{name: "status", options_query: "SELECT status FROM orders"}

      html =
        render_modal(dynamic_options: true, variable_data: variable, search_path: "reporting")

      assert html =~ ~s(phx-hook="OptionsSqlEditor")
      assert html =~ ~s(data-value="SELECT status FROM orders")
      assert html =~ "Test Query"
      assert html =~ "Runs on"
      assert html =~ "reporting"
      assert html =~ "The first column is the value"
    end
  end

  describe "sources that cannot populate options from a query" do
    test "offers the custom list and a saved query only" do
      html = render_modal(dynamic_options: false)

      assert html =~ "Custom list"
      assert html =~ "Saved query"
      refute html =~ "Pick a column"
      refute html =~ "Write SQL"
      refute html =~ "Test Query"
      assert html =~ "Enter one value per line"
    end

    test "falls back to manual entry for a variable carrying an options query" do
      variable = %QueryVariable{name: "status", options_query: "SELECT status FROM orders"}

      html = render_modal(dynamic_options: false, variable_data: variable)

      refute html =~ "Test Query"
      assert html =~ "Enter one value per line"
    end
  end

  describe "a saved query" do
    test "opens on the saved query a variable points at" do
      variable = %QueryVariable{name: "status", options_query_id: 7}
      saved = [%{id: 7, name: "Order statuses", data_source: "public"}]

      html = render_modal(dynamic_options: true, variable_data: variable, saved_queries: saved)

      assert html =~ ~s(<option value="7" selected>)
      assert html =~ "Order statuses"
      assert html =~ "Open this query"
    end

    test "names a saved query that no longer exists" do
      variable = %QueryVariable{name: "status", options_query_id: 99}

      html =
        render_modal(
          dynamic_options: true,
          variable_data: variable,
          saved_queries: [%{id: 7, name: "Other", data_source: "public"}]
        )

      assert html =~ "Query #99 (not found)"
    end
  end
end
