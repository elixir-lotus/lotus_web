if Code.ensure_loaded?(Sake.Server) do
  defmodule Lotus.Web.MCP.ChartApp do
    @moduledoc false
    # The MCP App show_chart names: one self-contained document, with the
    # chart bundle (assets/js/mcp/chart_app.js, built into
    # priv/static/mcp_chart.js) and Fude's style sheet (built into
    # priv/static/mcp_chart.css) inlined, so the host's sandbox needs no
    # network access at all. The chart itself is the server's HTML of it
    # (html/2), in show_chart's result, which the bundle mounts.
    use Sake.UI,
      uri: "ui://lotus/chart",
      name: "chart",
      title: "Lotus chart",
      description: "Draws a show_chart result.",
      scope: "lotus:query",
      prefers_border: true

    @external_resource script_path =
                         Application.app_dir(:lotus_web, ["priv", "static", "mcp_chart.js"])

    @script File.read!(script_path)

    @external_resource style_path =
                         Application.app_dir(:lotus_web, ["priv", "static", "mcp_chart.css"])

    @style File.read!(style_path)

    import Phoenix.Component, only: [sigil_H: 2]

    alias Lotus.Web.Charts
    alias Phoenix.HTML.Safe

    @doc "The HTML of the chart of a result and a config, which the app mounts."
    @spec html(map(), map()) :: String.t()
    def html(result, config) do
      assigns = %{result: result, config: config}

      ~H"""
      <Charts.draw id="lotus-chart" result={@result} config={@config} height={320} />
      """
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
    end

    @impl true
    def render(_ctx) do
      """
      <!doctype html>
      <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light dark; }
            body { margin: 0; padding: 12px 16px; font: 14px/1.4 system-ui, sans-serif; color: #111827; background: transparent; }
            [data-theme="dark"] body { color: #e5e7eb; }
            #title { margin: 0 0 8px; font-size: 15px; font-weight: 600; }
            #title:empty, #note:empty { display: none; }
            #chart { width: 100%; min-height: 40px; }
            #note { margin: 8px 0 0; font-size: 12px; opacity: 0.7; }
          </style>
          <style>#{@style}</style>
        </head>
        <body>
          <h1 id="title"></h1>
          <div id="chart"></div>
          <p id="note"></p>
          <script>#{@script}</script>
        </body>
      </html>
      """
    end
  end
end
