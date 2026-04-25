defmodule Lotus.Web.MixProject do
  use Mix.Project

  @source_url "https://github.com/typhoonworks/lotus_web"
  @version "0.14.5"

  def project do
    [
      app: :lotus_web,
      name: "Lotus Web",
      version: @version,
      elixir: "~> 1.17",
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
      {:phoenix_live_view, ">= 1.0.0 and < 1.2.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:gettext, "~> 0.26 or ~> 1.0"},
      {:earmark, "~> 1.4"},

      # Lotus
      {:lotus, "~> 0.16.4"},

      # Databases
      {:postgrex, "~> 0.20", only: [:dev, :test]},
      {:myxql, "~> 0.8", only: [:dev, :test]},

      # Tests
      {:floki, "~> 0.33", only: [:test, :dev]},

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

  defp aliases do
    [
      "assets.build": ["tailwind default", "esbuild default"],
      dev: "run --no-halt dev.exs",
      release: [
        "assets.build",
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
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/lotus_web",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/installation.md",
        "guides/getting-started.md",
        "guides/ai-assistant.md",
        "guides/visualizations.md",
        "guides/dashboards.md",
        "guides/variables-and-widgets.md"
      ]
    ]
  end

  defp description do
    """
    Web interface for Lotus — a LiveView-powered SQL editor, dashboard builder, and schema explorer that mounts directly in your Phoenix app.
    """
  end
end
