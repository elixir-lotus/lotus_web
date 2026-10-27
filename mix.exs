defmodule Lotus.Web.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-lotus/lotus_web"
  @version "2.0.0-dev"

  def project do
    [
      app: :lotus_web,
      name: "Lotus Web",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      dialyzer: dialyzer(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [preferred_envs: ["test.setup": :test, test: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Lotus.Web.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, ">= 1.1.0 and < 1.3.0"},
      {:jumon, "~> 0.2"},
      {:koyomi, "~> 0.2"},
      {:erabi, "~> 0.2"},
      {:kotoba, "~> 0.8"},
      {:masu, "~> 0.7"},
      # The charts.
      {:fude, "~> 0.7"},
      # The schema diagram.
      {:hakushi, "~> 0.6"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:gettext, "~> 0.26 or ~> 1.0"},
      {:mdex, "~> 0.13"},

      # Lotus
      # Temporarily on main, for Lotus.MCP.Host (elixir-lotus/lotus#343) and
      # :list_content (elixir-lotus/lotus#376), until the next Lotus release. Hex refuses to publish a git dependency.
      # On a branch for options_query_id until it is on main.
      # Overridden because Lotus's main is 2.0.0-dev, which the adapters'
      # `~> 1.3` doesn't match.
      {:lotus, github: "elixir-lotus/lotus", branch: "feat/saved-query-options", override: true},
      {:sake, "~> 0.4", optional: true},
      # The AI assistant. Optional, as in Lotus: a host that uses AI adds it.
      {:req_llm, "~> 1.29", optional: true},
      # Over HTTPS: the v2 branch's workflow fetches the dev deps with no SSH key.
      {:lotus_clickhouse, github: "elixir-lotus/lotus_clickhouse", branch: "main", only: :dev},
      {:lotus_elasticsearch,
       github: "elixir-lotus/lotus_elasticsearch", branch: "main", only: :dev},

      # Databases
      {:postgrex, "~> 0.20", only: [:dev, :test]},
      {:myxql, "~> 0.8", only: [:dev, :test]},
      {:ecto_ch, "~> 0.3", only: :dev},
      {:ecto_sqlite3, "~> 0.21", only: :dev},

      # Tests
      {:floki, "~> 0.33", only: [:test, :dev]},
      {:lazy_html, ">= 0.1.0", only: :test},

      # Dev Server
      {:bandit, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:tailwind, "~> 0.3", only: :dev, runtime: false},

      # Tooling
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false}
    ]
  end

  # Fude's maps (the world's countries, the US states), served by
  # Lotus.Web.Assets and fetched by the browser when a map chart draws.
  defp copy_maps(_args) do
    to = Path.join(["priv", "static", "maps"])
    File.mkdir_p!(to)

    for name <- ~w(world us-states) do
      File.cp!(
        Path.join(["deps", "fude", "priv", "static", "maps", "#{name}.json"]),
        Path.join(to, "#{name}.json")
      )
    end
  end

  defp aliases do
    [
      "assets.build": [
        "tailwind default",
        "esbuild default",
        "esbuild mcp_chart",
        "esbuild mcp_chart_css",
        &copy_maps/1
      ],
      dev: "run --no-halt dev.exs",
      # The compile and the asset build run in a child VM: once anything
      # compiles in this VM, Mix no longer finds the tasks of the Hex archive
      # (Elixir 1.20, Hex 2.5). hex.publish stays in this VM so that it can
      # read the two-factor code from the terminal.
      release: [
        "cmd mix assets.build",
        "hex.publish --yes",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "test.setup": ["ecto.drop --quiet", "ecto.create", "ecto.migrate"],
      lint: ["format", "dialyzer"]
    ]
  end

  defp package do
    [
      name: "lotus_web",
      maintainers: ["Arda Can Tugay", "Rui Freitas"],
      licenses: ["MIT"],
      links: %{GitHub: @source_url},
      files: ~w[lib priv/static* priv/gettext .formatter.exs mix.exs README* LICENSE*]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit, :ecto, :ecto_sql, :postgrex],
      plt_core_path: "_build/#{Mix.env()}",
      flags: [:error_handling, :missing_return, :underspecs],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Lotus Web",
      warnings_as_errors: true,
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/lotus_web",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/installation.md",
        "guides/getting-started.md",
        "guides/upgrading-to-v2.md",
        "guides/upgrading-to-v1.md",
        "guides/ai-assistant.md",
        "guides/visualizations.md",
        "guides/dashboards.md",
        "guides/variables-and-widgets.md",
        "guides/theming.md",
        "guides/mcp.md",
        "CONTRIBUTING.md",
        "SECURITY.md"
      ]
    ]
  end

  defp description do
    """
    Web interface for Lotus — a LiveView-powered SQL editor, dashboard builder, and schema explorer that mounts directly in your Phoenix app.
    """
  end
end
