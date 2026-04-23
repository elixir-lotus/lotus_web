import Config

if config_env() == :dev do
  config :esbuild,
    version: "0.25.0",
    default: [
      args: ~w(
        js/app.js
        --bundle
        --target=es2016
        --minify
        --outdir=../priv/static/
      ),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]

  config :tailwind,
    version: "3.4.0",
    default: [
      args: ~w(
        --config=tailwind.config.js
        --minify
        --input=css/app.css
        --output=../priv/static/css/app.css
      ),
      cd: Path.expand("../assets", __DIR__)
    ]
end

config :logger, level: :warning
config :logger, :console, format: "[$level] $message\n"

config :phoenix, stacktrace_depth: 20

config :lotus_web, :ecto_repos, [WebDev.Repo, WebDev.ReportingRepo]

config :lotus_web, Lotus.Web.Gettext,
  default_locale: "en",
  locales: ~w(en fr),
  priv: "priv/gettext"

config :lotus_web, Lotus.Web.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/postgres",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  url: System.get_env("POSTGRES_URL") || "postgres://localhost:5432/lotus_web_test"

config :lotus,
  storage_repo: WebDev.Repo,
  data_sources: %{
    "main" => WebDev.Repo
  }
