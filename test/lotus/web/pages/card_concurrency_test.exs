defmodule Lotus.Web.Pages.CardConcurrencyTest do
  # The /serial dashboard is mounted with `card_concurrency: 1`.
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Channel

  setup do
    dashboard = public_dashboard_fixture(%{name: "Serial Dashboard"})

    for {label, index} <- Enum.with_index(~w(card-one card-two card-three)) do
      query = query_fixture(%{name: label, statement: "SELECT '#{label}-result' AS label"})

      query_card_fixture(dashboard, query, %{
        title: label,
        position: index,
        layout: %{x: 0, y: index * 4, w: 6, h: 4}
      })
    end

    {:ok, dashboard: dashboard}
  end

  @results ~w(card-one-result card-two-result card-three-result)

  test "the dashboard view runs one card at a time and renders every card", %{
    dashboard: dashboard
  } do
    {:ok, live, _html} = live(build_conn(), "/serial/dashboards/#{dashboard.id}")

    html = await_cards(live)

    for result <- @results, do: assert(html =~ result)
  end

  test "the public view runs one card at a time and renders every card", %{
    dashboard: dashboard
  } do
    {:ok, live, _html} = live(build_conn(), "/serial/public/#{dashboard.public_token}")

    html = await_cards(live)

    for result <- @results, do: assert(html =~ result)
  end

  # `render_async/1` waits only for the tasks that run when it is called, and
  # the runner starts the next card when a result arrives.
  defp await_cards(live, tries \\ length(@results)) do
    assert {:ok, pids} = Channel.async_pids(live.pid)
    assert length(pids) <= 1

    html = render_async(live)

    if tries == 0 or Enum.all?(@results, &(html =~ &1)),
      do: html,
      else: await_cards(live, tries - 1)
  end
end
