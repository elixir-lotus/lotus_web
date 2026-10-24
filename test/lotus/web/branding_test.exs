defmodule Lotus.Web.BrandingTest do
  @moduledoc """
  A package brands the dashboard per request (`Lotus.Web.Pro.branding/1`).
  The package is stood in for through a setting, so these tests run alone.
  """
  use Lotus.Web.Case, async: false

  import Phoenix.LiveViewTest

  defmodule Package do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil

    def branding(info) do
      send(:persistent_term.get({__MODULE__, :test}), {:branding, info})
      :persistent_term.get({__MODULE__, :branding})
    end
  end

  defp brand(branding) do
    Application.put_env(:lotus_web, :__pro_web__, Package)
    :persistent_term.put({Package, :test}, self())
    :persistent_term.put({Package, :branding}, branding)

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({Package, :test})
      :persistent_term.erase({Package, :branding})
    end)
  end

  test "without a package, the dashboard is Lotus" do
    {:ok, _live, html} = live(build_conn(), "/lotus")

    assert html =~ "<title>Lotus Dashboard</title>"
    assert html =~ "lotus-wordmark"

    dashboard = public_dashboard_fixture(%{name: "Sales"})
    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
    assert html =~ "Powered by"
  end

  test "a package names the product, shows its logo, and sets the theme and colours" do
    brand(%{
      product_name: "Acme Insights",
      logo: "https://cdn.acme.test/logo.svg",
      theme: :sumi,
      theme_colors: %{"pink-600" => "#0ea5e9"}
    })

    {:ok, _live, html} = live(build_conn(), "/lotus")

    assert html =~ "<title>Acme Insights Dashboard</title>"
    assert html =~ ~s(src="https://cdn.acme.test/logo.svg")
    assert html =~ ~s(alt="Acme Insights")
    refute html =~ "lotus-wordmark"
    assert html =~ ~s(data-lotus-theme="sumi")
    assert html =~ "#0ea5e9" or html =~ "14 165 233"

    assert_received {:branding, %{public: false, dashboard: nil}}
  end

  test "a name without a logo shows the name, not the Lotus mark" do
    brand(%{product_name: "Acme Insights"})

    {:ok, _live, html} = live(build_conn(), "/lotus")

    assert html =~ "Acme Insights"
    refute html =~ "lotus-wordmark"
  end

  test "what is not valid is ignored" do
    brand(%{
      product_name: "  ",
      logo: "javascript:alert(1)",
      theme: :neon,
      theme_colors: %{"pink-600" => "red"}
    })

    {:ok, _live, html} = live(build_conn(), "/lotus")

    assert html =~ "<title>Lotus Dashboard</title>"
    refute html =~ "javascript:"
    assert html =~ ~s(data-lotus-theme="lotus")
    refute html =~ "pink-600: red"
  end

  test "a public dashboard is branded for its dashboard, and keeps Powered by Lotus" do
    brand(%{product_name: "Acme Insights", powered_by: false})
    dashboard = public_dashboard_fixture(%{name: "Sales"})

    {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

    assert html =~ "Powered by"
    id = dashboard.id
    assert_received {:branding, %{public: true, dashboard: %{id: ^id}}}
  end

  test "a package names the assistant" do
    brand(%{assistant_name: "Acme Copilot"})
    Application.put_env(:lotus, :ai, enabled: true, api_key: "sk-test")
    Lotus.Config.reload!()

    on_exit(fn ->
      Application.delete_env(:lotus, :ai)
      Lotus.Config.reload!()
    end)

    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    render_async(live)
    live |> element("#ai-assistant-btn") |> render_click()

    assert render(live) =~ "Acme Copilot"
  end
end
