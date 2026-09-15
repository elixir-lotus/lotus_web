defmodule Lotus.Web.Dashboards.CardComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Lotus.Web.Dashboards.CardComponent

  # A table card shows the first rows of a result. Every value must render the
  # way the editor renders it: a Decimal as a number, not as its inspect form.
  test "a table card formats a Decimal, a date and nil like the editor does" do
    result = %Lotus.Result{
      columns: ["city", "lifetime_value", "since", "notes"],
      rows: [["Chicago", Decimal.new("1250.50"), ~D[2026-09-15], nil]],
      num_rows: 1,
      duration_ms: 1
    }

    html =
      render_component(CardComponent,
        id: "card-1",
        card: %{
          id: 1,
          card_type: :query,
          title: "Customers",
          content: %{},
          layout: %{x: 0, y: 0, w: 6, h: 4},
          visualization_config: %{}
        },
        result: result,
        error: nil,
        running: false,
        selected: false,
        can_manage: false,
        parent: nil,
        public: true
      )

    assert html =~ "1250.50"
    refute html =~ "Decimal.new"
    assert html =~ "2026-09-15"
    assert html =~ ~r/>\s*-\s*</
  end
end
