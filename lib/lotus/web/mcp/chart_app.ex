if Code.ensure_loaded?(Sake.Server) do
  defmodule Lotus.Web.MCP.ChartApp do
    @moduledoc false
    # The MCP App show_chart names: one self-contained document, with the
    # chart bundle (assets/js/mcp/chart_app.js, built into
    # priv/static/mcp_chart.js) inlined, so the host's sandbox needs no
    # network access at all.
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
