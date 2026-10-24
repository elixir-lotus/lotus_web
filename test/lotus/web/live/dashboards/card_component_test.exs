defmodule Lotus.Web.Dashboards.CardComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Lotus.Result
  alias Lotus.Web.Dashboards.CardComponent

  # A table card is the editor's grid, read-only: every value as the editor
  # has it, a Decimal as a number (not its inspect form), and its column of
  # the type of its values.
  test "a table card gives Masu a Decimal, a date and nil as the editor does" do
    result = %Result{
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

    assert html =~ ~s(id="table-1" class="masu)
    assert html =~ "[[0,&quot;Chicago&quot;,&quot;1250.50&quot;,&quot;2026-09-15&quot;,null]]"
    refute html =~ "Decimal.new"
    assert html =~ "&quot;key&quot;:&quot;lifetime_value&quot;"
    assert html =~ "&quot;type&quot;:&quot;decimal&quot;"
  end

  test "a card reading its data shows the shape of what comes, not a spinner" do
    base = %{
      id: 2,
      card_type: :query,
      title: "Revenue",
      content: %{},
      layout: %{x: 0, y: 0, w: 6, h: 4}
    }

    render = fn config ->
      render_component(CardComponent,
        id: "card-2",
        card: Map.put(base, :visualization_config, config),
        result: nil,
        error: nil,
        running: true,
        selected: false,
        can_manage: false,
        parent: nil,
        public: true
      )
    end

    chart = render.(%{"chart_type" => "bar", "x_field" => "region", "y_field" => "revenue"})
    assert chart =~ ~s(class="lotus-card-placeholder)
    assert chart =~ ~s(role="status")
    assert chart =~ "height: 95%"

    table = render.(%{})
    assert table =~ ~s(class="lotus-card-placeholder)
    refute table =~ "height: 95%"
  end
end
