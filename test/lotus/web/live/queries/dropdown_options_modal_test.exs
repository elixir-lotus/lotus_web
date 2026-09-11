defmodule Lotus.Web.Queries.DropdownOptionsModalTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Lotus.Storage.QueryVariable
  alias Lotus.Web.Queries.DropdownOptionsModal

  defp render_modal(opts) do
    render_component(DropdownOptionsModal,
      id: "dropdown_options_modal",
      variable_name: "status",
      variable_data: Keyword.get(opts, :variable_data, %QueryVariable{name: "status"}),
      dynamic_options: Keyword.fetch!(opts, :dynamic_options),
      parent: nil
    )
  end

  describe "sources that can populate options from a query" do
    test "offers both the custom list and the query" do
      html = render_modal(dynamic_options: true)

      assert html =~ "Custom list"
      assert html =~ "From query"
    end

    test "opens on the query tab for a variable already populated from a query" do
      variable = %QueryVariable{name: "status", options_query: "SELECT status FROM orders"}

      html = render_modal(dynamic_options: true, variable_data: variable)

      assert html =~ "Test Query"
      assert html =~ "SELECT status FROM orders"
    end
  end

  describe "sources that cannot populate options from a query" do
    test "offers manual entry only" do
      html = render_modal(dynamic_options: false)

      refute html =~ "Custom list"
      refute html =~ "From query"
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
end
