defmodule Lotus.Web.BrandingTest do
  @moduledoc """
  Only Lotus Pro brands the dashboard. The free version is always Lotus: the
  router takes no branding options, and without Pro the name, the logo and
  the "Powered by Lotus" footer are Lotus's. With Pro installed, Lotus asks
  `Lotus.Pro.Web.branding/1` (through `Lotus.Web.Pro.branding/1`) for each
  request's branding, and even then the footer stays.

  `ProWeb` below stands in for `Lotus.Pro.Web`, set through a setting, so
  these tests run alone.
  """
  use Lotus.Web.Case, async: false

  import Phoenix.LiveViewTest

  defmodule ProWeb do
    @moduledoc false

    def pages, do: []
    def nav_items(_assigns), do: []
    def render_slot(_name, _assigns), do: nil

    def branding(info) do
      send(:persistent_term.get({__MODULE__, :test}), {:branding, info})
      :persistent_term.get({__MODULE__, :branding})
    end
  end

  # Installs the stand-in for Lotus Pro, answering `branding`.
  defp with_pro(branding) do
    Application.put_env(:lotus_web, :__pro_web__, ProWeb)
    :persistent_term.put({ProWeb, :test}, self())
    :persistent_term.put({ProWeb, :branding}, branding)

    on_exit(fn ->
      Application.delete_env(:lotus_web, :__pro_web__)
      :persistent_term.erase({ProWeb, :test})
      :persistent_term.erase({ProWeb, :branding})
    end)
  end

  describe "the free version, without Lotus Pro" do
    test "is Lotus: its name, its mark and Powered by Lotus" do
      refute Lotus.Web.Pro.available?()

      {:ok, _live, html} = live(build_conn(), "/lotus")
      assert html =~ "<title>Lotus Dashboard</title>"
      assert html =~ "lotus-wordmark"

      dashboard = public_dashboard_fixture(%{name: "Sales"})
      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")
      assert html =~ "Powered by"
    end

    test "has no branding options: the router refuses them" do
      for option <- [product_name: "Acme", logo: "/acme.svg", assistant_name: "Acme AI"] do
        assert_raise ArgumentError, ~r/invalid option for lotus_dashboard/, fn ->
          Lotus.Web.Router.__options__("/lotus", [option])
        end
      end
    end
  end

  describe "with Lotus Pro" do
    test "Pro names the product, shows its logo, and sets the theme and colours" do
      with_pro(%{
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
      with_pro(%{product_name: "Acme Insights"})

      {:ok, _live, html} = live(build_conn(), "/lotus")

      assert html =~ "Acme Insights"
      refute html =~ "lotus-wordmark"
    end

    test "Pro answering no branding leaves the dashboard Lotus" do
      with_pro(%{})

      {:ok, _live, html} = live(build_conn(), "/lotus")

      assert html =~ "<title>Lotus Dashboard</title>"
      assert html =~ "lotus-wordmark"
    end

    test "what Pro gives that is not valid is ignored" do
      with_pro(%{
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

    test "a public dashboard is branded for its dashboard, and still says Powered by Lotus" do
      with_pro(%{product_name: "Acme Insights", powered_by: false})
      dashboard = public_dashboard_fixture(%{name: "Sales"})

      {:ok, _live, html} = live(build_conn(), "/lotus/public/#{dashboard.public_token}")

      assert html =~ "Powered by"
      id = dashboard.id
      assert_received {:branding, %{public: true, dashboard: %{id: ^id}}}
    end

    test "Pro names the assistant" do
      with_pro(%{assistant_name: "Acme Copilot"})
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
end
