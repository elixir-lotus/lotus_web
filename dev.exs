# Development server for Lotus Web

# Repos

defmodule WebDev.PostgresRepo do
  use Ecto.Repo, otp_app: :lotus_web, adapter: Ecto.Adapters.Postgres
end

defmodule WebDev.MySQLRepo do
  use Ecto.Repo, otp_app: :lotus_web, adapter: Ecto.Adapters.MyXQL
end

defmodule WebDev.SQLiteRepo do
  use Ecto.Repo, otp_app: :lotus_web, adapter: Ecto.Adapters.SQLite3
end

defmodule WebDev.ClickHouseRepo do
  use Ecto.Repo, otp_app: :lotus_web, adapter: Ecto.Adapters.ClickHouse
end

defmodule WebDev.SearchClient do
  use Lotus.Elasticsearch, otp_app: :lotus_web
end

defmodule WebDev.Migration0 do
  use Ecto.Migration

  def change do
    # Create sample tables for demonstration in public schema
    create table(:users) do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:status, :string, default: "active")
      add(:age, :integer)
      timestamps(type: :utc_datetime)
    end

    create table(:posts) do
      add(:title, :string, null: false)
      add(:content, :text)
      add(:published, :boolean, default: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      timestamps(type: :utc_datetime)
    end

    create table(:orders) do
      add(:total_amount, :decimal, precision: 10, scale: 2)
      add(:status, :string, default: "pending")
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      timestamps(type: :utc_datetime)
    end

    create(index(:users, [:email]))
    create(index(:posts, [:user_id]))
    create(index(:posts, [:published]))
    create(index(:orders, [:user_id]))
    create(index(:orders, [:status]))
  end
end

defmodule WebDev.Migration1 do
  use Ecto.Migration

  def change do
    execute(
      "CREATE SCHEMA IF NOT EXISTS reporting",
      "DROP SCHEMA IF EXISTS reporting CASCADE"
    )

    create table(:customers, prefix: "reporting") do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:active, :boolean, default: true)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:customers, [:email], prefix: "reporting"))

    create table(:invoices, prefix: "reporting") do
      add(:customer_id, references(:customers, on_delete: :delete_all, prefix: "reporting"),
        null: false
      )

      add(:total_amount, :decimal, precision: 10, scale: 2)
      add(:status, :string, default: "open")
      timestamps(type: :utc_datetime)
    end

    create(index(:invoices, [:customer_id], prefix: "reporting"))

    execute(
      "COMMENT ON TABLE reporting.customers IS 'Reporting demo table'",
      "COMMENT ON TABLE reporting.customers IS NULL"
    )
  end
end

defmodule WebDev.Migration2 do
  use Ecto.Migration

  def up do
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end

defmodule WebDev.Migration3 do
  use Ecto.Migration

  def up do
    # Re-run Lotus migrations to pick up V2 (visualizations table)
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end

defmodule WebDev.Migration4 do
  use Ecto.Migration

  def up do
    # Re-run Lotus migrations to pick up V3 (dashboard tables)
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end

defmodule WebDev.Migration5 do
  use Ecto.Migration

  def up do
    # Re-run Lotus migrations to pick up V5 (query language) and V6 (cascading filters)
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end

defmodule WebDev.MySQLMigration do
  use Ecto.Migration

  def change do
    # Create sample tables in MySQL
    create table(:products) do
      add(:name, :string, null: false)
      add(:price, :decimal, precision: 10, scale: 2)
      add(:category, :string)
      add(:in_stock, :boolean, default: true)
      timestamps(type: :utc_datetime)
    end

    create table(:sales) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      add(:quantity, :integer, null: false)
      add(:total_price, :decimal, precision: 10, scale: 2)
      add(:sale_date, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(index(:sales, [:product_id]))
    create(index(:sales, [:sale_date]))
  end
end

# Phoenix

defmodule WebDev.Router do
  use Phoenix.Router, helpers: false

  import Lotus.Web.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_flash)
  end

  scope "/" do
    pipe_through(:browser)

    lotus_dashboard("/lotus", features: [:timeout_options])
  end
end

defmodule WebDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :lotus_web

  socket("/live", Phoenix.LiveView.Socket)
  socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)

  plug(Phoenix.LiveReloader)
  plug(Phoenix.CodeReloader)

  plug(Plug.Static,
    at: "/",
    from: :lotus_web,
    only: ~w(app.css app.js fonts images favicon.ico robots.txt)
  )

  plug(Plug.Session,
    store: :cookie,
    key: "_lotus_web_key",
    signing_salt: "GB8lUrg7Zv8Pkt"
  )

  plug(WebDev.Router)
end

defmodule WebDev.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

# Configuration

# Pick backends with e.g. `BACKENDS=postgres,sqlite mix dev`; defaults to all.
all_backends = ~w(postgres mysql sqlite clickhouse elasticsearch)

backends =
  case System.get_env("BACKENDS") do
    nil -> all_backends
    list -> list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

case backends -- all_backends do
  [] ->
    :ok

  unknown ->
    raise "Unknown BACKENDS: #{Enum.join(unknown, ", ")}. Valid: #{Enum.join(all_backends, ", ")}"
end

# Postgres always runs: it stores Lotus' own queries and dashboards.
backends = Enum.uniq(["postgres" | backends])
on? = &(&1 in backends)

port = "PORT" |> System.get_env("4000") |> String.to_integer()

Application.put_env(:lotus_web, WebDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  debug_errors: true,
  http: [port: port],
  live_view: [signing_salt: "UuMMKJSRnB6z91GJflEeqpp2M4lVgFc4"],
  pubsub_server: WebDev.PubSub,
  render_errors: [formats: [html: WebDev.ErrorHTML], layout: false],
  secret_key_base: "HYusO/Y1jNCOL7KxqmWuDTL74SasPCN2D7tbh2dLyKemStwCg2GhqINb4JFt1DFj",
  url: [host: "localhost"],
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/lotus/web/(pages|live|components)/.*(ex|heex)$"
    ]
  ]
)

Application.put_env(:lotus_web, WebDev.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 2346,
  database: "lotus_web_dev"
)

Application.put_env(:lotus_web, WebDev.MySQLRepo,
  username: "lotus",
  password: "lotus",
  hostname: "localhost",
  port: 3308,
  database: "lotus_web_dev"
)

Application.put_env(:lotus_web, WebDev.SQLiteRepo,
  database: Path.expand("priv/lotus_web_dev.db", __DIR__)
)

Application.put_env(:lotus_web, WebDev.ClickHouseRepo,
  hostname: "localhost",
  port: 9123,
  scheme: "http",
  database: "lotus_web_dev",
  username: "default",
  password: "clickhouse",
  pool_size: 5,
  settings: []
)

Application.put_env(:lotus_web, WebDev.SearchClient, url: "http://localhost:9209")

Application.put_env(:phoenix, :serve_endpoints, true)
Application.put_env(:phoenix, :persistent, true)

# Configure Lotus with the development repos
Application.put_env(:lotus, :storage_repo, WebDev.PostgresRepo)
Application.put_env(:lotus, :default_source, "postgres")

Application.put_env(
  :lotus,
  :data_sources,
  Map.take(
    %{
      "postgres" => WebDev.PostgresRepo,
      "mysql" => WebDev.MySQLRepo,
      "sqlite" => WebDev.SQLiteRepo,
      "clickhouse" => WebDev.ClickHouseRepo,
      "elasticsearch" => %{
        adapter: :elasticsearch,
        url: "http://localhost:9209",
        allow_unrestricted_resources: true
      }
    },
    backends
  )
)

Application.put_env(
  :lotus,
  :source_adapters,
  for(
    {backend, adapter} <- [
      {"clickhouse", Lotus.Source.Adapters.ClickHouse},
      {"elasticsearch", Lotus.Source.Adapters.Elasticsearch}
    ],
    on?.(backend),
    do: adapter
  )
)

# Configure Lotus caching
Application.put_env(:lotus, :cache, %{
  adapter: Lotus.Cache.ETS,
  namespace: "lotus_web_dev"
})

# Import dev secrets (API keys, etc.) if the file exists
# Generate with: mix lotus.gen.dev.secret
dev_secret_exs_path = Path.expand("config/dev.secret.exs", __DIR__)

if File.exists?(dev_secret_exs_path) do
  Code.eval_file(dev_secret_exs_path)
  IO.puts("✅ Loaded dev.secret.exs configuration")
else
  IO.puts("⚠️  dev.secret.exs not found. AI features will be disabled.")
  IO.puts("   Run 'mix lotus.gen.dev.secret' to create it with API key placeholders.")
end

Task.async(fn ->
  # Fude from GitHub: its browser files, before the watchers bundle them.
  Mix.Task.run("fude.git_assets")

  # Start esbuild and tailwind applications first
  {:ok, _} = Application.ensure_all_started(:esbuild)
  {:ok, _} = Application.ensure_all_started(:tailwind)

  IO.puts("🔄 Starting dev server...")

  repos =
    for {backend, repo} <- [
          {"postgres", WebDev.PostgresRepo},
          {"mysql", WebDev.MySQLRepo},
          {"sqlite", WebDev.SQLiteRepo},
          {"clickhouse", WebDev.ClickHouseRepo}
        ],
        on?.(backend),
        do: {repo, []}

  children =
    [{Phoenix.PubSub, [name: WebDev.PubSub, adapter: Phoenix.PubSub.PG2]}] ++
      repos ++ [{WebDev.Endpoint, []}]

  # Set up PostgreSQL
  Ecto.Adapters.Postgres.storage_up(WebDev.PostgresRepo.config())

  # Set up MySQL
  if on?.("mysql"), do: Ecto.Adapters.MyXQL.storage_up(WebDev.MySQLRepo.config())

  # Create the file up front; letting the pool race to create it locks the database
  if on?.("sqlite"), do: Ecto.Adapters.SQLite3.storage_up(WebDev.SQLiteRepo.config())

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

  # Lotus auto-starts as an OTP app (mod: Lotus.Application in mix.exs).
  # Reload config so it picks up the data_sources/source_adapters we set above.
  Lotus.Config.reload!()

  # Run PostgreSQL migrations
  Ecto.Migrator.run(
    WebDev.PostgresRepo,
    [
      # public.users/posts/orders
      {0, WebDev.Migration0},
      # reporting.customers/invoices
      {1, WebDev.Migration1},
      # Lotus.Migrations.up() - V1
      {2, WebDev.Migration2},
      # Lotus.Migrations.up() - V2 (visualizations)
      {3, WebDev.Migration3},
      # Lotus.Migrations.up() - V3 (dashboards)
      {4, WebDev.Migration4},
      # Lotus.Migrations.up() - V5 (query language), V6 (cascading filters)
      {5, WebDev.Migration5}
    ],
    :up,
    all: true
  )

  # MySQL and SQLite share the products/sales schema and seed data
  for {backend, repo} <- [{"mysql", WebDev.MySQLRepo}, {"sqlite", WebDev.SQLiteRepo}],
      on?.(backend) do
    Ecto.Migrator.run(repo, [{0, WebDev.MySQLMigration}], :up, all: true)
  end

  if on?.("clickhouse") do
    # Create ClickHouse tables (no Ecto migrations for ClickHouse)
    WebDev.ClickHouseRepo.query!("""
    CREATE TABLE IF NOT EXISTS events (
      id UInt64,
      event_name String,
      user_id UInt64,
      properties String DEFAULT '{}',
      revenue Nullable(Float64),
      occurred_at DateTime DEFAULT now()
    ) ENGINE = MergeTree() ORDER BY (event_name, occurred_at)
    """)

    WebDev.ClickHouseRepo.query!("""
    CREATE TABLE IF NOT EXISTS page_views (
      id UInt64,
      url String,
      user_id UInt64,
      duration_ms UInt32 DEFAULT 0,
      country LowCardinality(String) DEFAULT '',
      browser LowCardinality(String) DEFAULT '',
      viewed_at DateTime DEFAULT now()
    ) ENGINE = MergeTree() ORDER BY (url, viewed_at)
    """)
  end

  # --- DESTROY ALL EXISTING DATA ---

  if on?.("clickhouse") do
    WebDev.ClickHouseRepo.query!("TRUNCATE TABLE IF EXISTS events")
    WebDev.ClickHouseRepo.query!("TRUNCATE TABLE IF EXISTS page_views")
  end

  if on?.("elasticsearch") do
    # Create OpenSearch indices and seed data
    es_url = "http://localhost:9209"

    Lotus.Elasticsearch.Client.request(:delete, es_url, "/dev_logs")

    Lotus.Elasticsearch.Client.request(:put, es_url, "/dev_logs",
      json: %{
        mappings: %{
          properties: %{
            level: %{type: "keyword"},
            service: %{type: "keyword"},
            message: %{type: "text"},
            status_code: %{type: "integer"},
            duration_ms: %{type: "float"},
            timestamp: %{type: "date"}
          }
        }
      }
    )

    for doc <- [
          %{
            level: "info",
            service: "api",
            message: "GET /users 200",
            status_code: 200,
            duration_ms: 12.5,
            timestamp: "2024-01-15T10:00:00Z"
          },
          %{
            level: "info",
            service: "api",
            message: "POST /orders 201",
            status_code: 201,
            duration_ms: 45.2,
            timestamp: "2024-01-15T10:01:00Z"
          },
          %{
            level: "warn",
            service: "worker",
            message: "Job retry attempt 2",
            status_code: nil,
            duration_ms: nil,
            timestamp: "2024-01-15T10:02:00Z"
          },
          %{
            level: "error",
            service: "api",
            message: "GET /reports 500",
            status_code: 500,
            duration_ms: 230.1,
            timestamp: "2024-01-15T10:03:00Z"
          },
          %{
            level: "info",
            service: "web",
            message: "GET /dashboard 200",
            status_code: 200,
            duration_ms: 8.3,
            timestamp: "2024-01-15T10:04:00Z"
          },
          %{
            level: "info",
            service: "api",
            message: "GET /products 200",
            status_code: 200,
            duration_ms: 15.7,
            timestamp: "2024-01-15T10:05:00Z"
          },
          %{
            level: "error",
            service: "worker",
            message: "Connection refused to redis",
            status_code: nil,
            duration_ms: nil,
            timestamp: "2024-01-15T10:06:00Z"
          },
          %{
            level: "info",
            service: "web",
            message: "GET /login 200",
            status_code: 200,
            duration_ms: 5.1,
            timestamp: "2024-01-15T10:07:00Z"
          }
        ] do
      Lotus.Elasticsearch.Client.request(:post, es_url, "/dev_logs/_doc?refresh=true", json: doc)
    end
  end

  WebDev.PostgresRepo.query!("TRUNCATE TABLE users, posts, orders RESTART IDENTITY CASCADE")

  WebDev.PostgresRepo.query!(
    "TRUNCATE TABLE reporting.customers, reporting.invoices RESTART IDENTITY CASCADE"
  )

  # --- POSTGRESQL DATA ---

  # Users
  WebDev.PostgresRepo.query!(
    "INSERT INTO users (name, email, age, status, inserted_at, updated_at) VALUES
    ('Alice', 'alice@example.com', 30, 'active', now(), now()),
    ('Bob',   'bob@example.com',   25, 'inactive', now(), now()),
    ('Charlie','charlie@example.com', 40, 'active', now(), now()),
    ('Diana', 'diana@example.com', 35, 'active', now(), now()),
    ('Eve',   'eve@example.com',   28, 'active', now(), now())
  "
  )

  # Posts
  WebDev.PostgresRepo.query!(
    "INSERT INTO posts (title, content, user_id, published, inserted_at, updated_at) VALUES
    ('Hello World',     'First post!', 1, true,  now(), now()),
    ('Draft Thoughts',  'Unpublished idea', 1, false, now(), now()),
    ('Bob''s Adventures','Exploring Elixir', 2, true,  now(), now()),
    ('Security Notes',  'Eve on crypto', 5, true,  now(), now()),
    ('Cooking with SQL','Charlie''s recipe', 3, false, now(), now())
  "
  )

  # Orders
  WebDev.PostgresRepo.query!(
    "INSERT INTO orders (total_amount, status, user_id, inserted_at, updated_at) VALUES
    (49.99,  'pending',  1, now(), now()),
    (19.50,  'completed',2, now(), now()),
    (200.00, 'completed',3, now(), now()),
    (75.25,  'pending',  1, now(), now()),
    (300.10, 'shipped',  4, now(), now())
  "
  )

  # Reporting Customers - some with matching user emails for cross-schema queries
  WebDev.PostgresRepo.query!(
    "INSERT INTO reporting.customers (name, email, active, inserted_at, updated_at) VALUES
    ('Alice Consulting', 'alice@example.com',     true,  now(), now()),
    ('Bob Enterprises',  'bob@example.com',       true,  now(), now()),
    ('Initech',         'hello@initech.com',      false, now(), now()),
    ('Diana Corp',      'diana@example.com',      true,  now(), now())
  "
  )

  # Reporting Invoices
  WebDev.PostgresRepo.query!(
    "INSERT INTO reporting.invoices (customer_id, total_amount, status, inserted_at, updated_at) VALUES
    (1, 199.99, 'open',     now(), now()),
    (1, 500.00, 'paid',     now(), now()),
    (2, 250.00, 'overdue',  now(), now()),
    (3, 1000.00,'paid',     now(), now()),
    (4, 75.00,  'open',     now(), now())
  "
  )

  # --- MYSQL / SQLITE DATA ---

  for {backend, repo} <- [{"mysql", WebDev.MySQLRepo}, {"sqlite", WebDev.SQLiteRepo}],
      on?.(backend) do
    repo.query!("DELETE FROM sales")
    repo.query!("DELETE FROM products")

    # CURRENT_TIMESTAMP is UTC on both MySQL and SQLite
    repo.query!(
      "INSERT INTO products (name, price, category, in_stock, inserted_at, updated_at) VALUES
      ('Laptop Pro', 1299.99, 'Electronics', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('Wireless Mouse', 29.99, 'Electronics', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('Office Chair', 199.50, 'Furniture', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('Coffee Mug', 12.99, 'Kitchen', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('Notebook', 5.99, 'Stationery', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    "
    )

    %{rows: product_rows} = repo.query!("SELECT id FROM products ORDER BY id")
    [laptop_id, mouse_id, _chair_id, mug_id, notebook_id] = Enum.map(product_rows, &List.first/1)

    repo.query!(
      "INSERT INTO sales (product_id, quantity, total_price, sale_date, inserted_at, updated_at) VALUES
      (#{laptop_id}, 2, 2599.98, '2024-01-15 10:30:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      (#{mouse_id}, 5, 149.95, '2024-01-16 14:22:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      (#{mug_id}, 10, 129.90, '2024-01-17 09:45:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      (#{notebook_id}, 3, 17.97, '2024-01-18 16:10:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      (#{laptop_id}, 1, 1299.99, '2024-01-19 11:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    "
    )
  end

  # --- CLICKHOUSE DATA ---

  if on?.("clickhouse") do
    # Events (analytics-style data)
    WebDev.ClickHouseRepo.query!("""
    INSERT INTO events (id, event_name, user_id, properties, revenue, occurred_at) VALUES
      (1, 'page_view',    1, '{"page": "/home"}',        NULL, '2024-01-15 10:00:00'),
      (2, 'sign_up',      2, '{"source": "google"}',     NULL, '2024-01-15 10:05:00'),
      (3, 'purchase',     1, '{"product": "Pro Plan"}',   49.99, '2024-01-15 10:30:00'),
      (4, 'page_view',    3, '{"page": "/pricing"}',      NULL, '2024-01-15 11:00:00'),
      (5, 'purchase',     3, '{"product": "Team Plan"}',  199.00, '2024-01-15 11:15:00'),
      (6, 'page_view',    1, '{"page": "/dashboard"}',    NULL, '2024-01-16 09:00:00'),
      (7, 'feature_use',  1, '{"feature": "export"}',     NULL, '2024-01-16 09:30:00'),
      (8, 'sign_up',      4, '{"source": "referral"}',    NULL, '2024-01-16 14:00:00'),
      (9, 'purchase',     4, '{"product": "Pro Plan"}',   49.99, '2024-01-16 14:10:00'),
      (10, 'page_view',   5, '{"page": "/home"}',         NULL, '2024-01-17 08:00:00'),
      (11, 'sign_up',     5, '{"source": "organic"}',     NULL, '2024-01-17 08:05:00'),
      (12, 'feature_use', 2, '{"feature": "query"}',      NULL, '2024-01-17 10:00:00'),
      (13, 'purchase',    2, '{"product": "Enterprise"}',  499.00, '2024-01-17 10:30:00'),
      (14, 'page_view',   3, '{"page": "/docs"}',         NULL, '2024-01-18 11:00:00'),
      (15, 'feature_use', 3, '{"feature": "dashboard"}',  NULL, '2024-01-18 11:30:00')
    """)

    # Page views (web analytics-style data)
    WebDev.ClickHouseRepo.query!("""
    INSERT INTO page_views (id, url, user_id, duration_ms, country, browser, viewed_at) VALUES
      (1,  '/home',       1, 3200, 'US', 'Chrome',  '2024-01-15 10:00:00'),
      (2,  '/pricing',    1, 8500, 'US', 'Chrome',  '2024-01-15 10:02:00'),
      (3,  '/signup',     2, 1200, 'UK', 'Firefox', '2024-01-15 10:04:00'),
      (4,  '/pricing',    3, 12000,'DE', 'Safari',  '2024-01-15 11:00:00'),
      (5,  '/docs',       3, 45000,'DE', 'Safari',  '2024-01-15 11:05:00'),
      (6,  '/dashboard',  1, 60000,'US', 'Chrome',  '2024-01-16 09:00:00'),
      (7,  '/settings',   1, 5000, 'US', 'Chrome',  '2024-01-16 09:15:00'),
      (8,  '/home',       4, 2000, 'FR', 'Chrome',  '2024-01-16 14:00:00'),
      (9,  '/pricing',    4, 7000, 'FR', 'Chrome',  '2024-01-16 14:02:00'),
      (10, '/home',       5, 1500, 'JP', 'Edge',    '2024-01-17 08:00:00'),
      (11, '/docs',       5, 30000,'JP', 'Edge',    '2024-01-17 08:10:00'),
      (12, '/dashboard',  2, 90000,'UK', 'Firefox', '2024-01-17 10:00:00'),
      (13, '/home',       3, 1800, 'DE', 'Safari',  '2024-01-18 11:00:00'),
      (14, '/docs',       3, 25000,'DE', 'Safari',  '2024-01-18 11:05:00'),
      (15, '/pricing',    5, 9000, 'JP', 'Edge',    '2024-01-18 12:00:00')
    """)
  end

  # --- LOTUS QUERIES & DASHBOARDS ---

  # Clear existing Lotus data (tables created by migrations above)
  WebDev.PostgresRepo.query!("DELETE FROM lotus_dashboard_card_filter_mappings")
  WebDev.PostgresRepo.query!("DELETE FROM lotus_dashboard_filters")
  WebDev.PostgresRepo.query!("DELETE FROM lotus_dashboard_cards")
  WebDev.PostgresRepo.query!("DELETE FROM lotus_dashboards")
  WebDev.PostgresRepo.query!("DELETE FROM lotus_query_visualizations")
  WebDev.PostgresRepo.query!("DELETE FROM lotus_queries")

  # Create sample queries
  {:ok, users_query} =
    Lotus.create_query(%{
      name: "All Users",
      description: "List all users with their status",
      statement:
        "SELECT id, name, email, age, status FROM users WHERE 1=1 [[AND name ILIKE {{name}} || '%']] ORDER BY id",
      variables: [
        %{name: "name", type: :text, label: "Name"}
      ]
    })

  {:ok, orders_query} =
    Lotus.create_query(%{
      name: "Orders by Status",
      description: "Order totals grouped by status",
      statement:
        "SELECT status, COUNT(*) as count, SUM(total_amount) as total FROM orders GROUP BY status ORDER BY total DESC"
    })

  {:ok, user_posts_query} =
    Lotus.create_query(%{
      name: "User Posts",
      description: "Posts with their authors",
      statement:
        "SELECT u.name as author, p.title, p.published FROM posts p JOIN users u ON p.user_id = u.id WHERE 1=1 [[AND u.name ILIKE {{author}} || '%']] ORDER BY p.id",
      variables: [
        %{name: "author", type: :text, label: "Author"}
      ]
    })

  {:ok, invoices_query} =
    Lotus.create_query(%{
      name: "Invoice Summary",
      description: "Invoice totals by status",
      statement:
        "SELECT status, COUNT(*) as count, SUM(total_amount) as total FROM reporting.invoices GROUP BY status"
    })

  if on?.("clickhouse") do
    {:ok, _events_query} =
      Lotus.create_query(%{
        name: "Events by Type",
        description: "ClickHouse event counts by type",
        data_source: "clickhouse",
        statement:
          "SELECT event_name, uniq(user_id) AS unique_users, count() AS total_events FROM events GROUP BY event_name ORDER BY total_events DESC"
      })

    {:ok, _pageviews_query} =
      Lotus.create_query(%{
        name: "Page Views by Country",
        description: "ClickHouse page view analytics",
        data_source: "clickhouse",
        statement:
          "SELECT country, count() AS views, round(avg(duration_ms) / 1000, 1) AS avg_duration_sec, uniq(user_id) AS unique_visitors FROM page_views GROUP BY country ORDER BY views DESC"
      })
  end

  if on?.("elasticsearch") do
    {:ok, _logs_query} =
      Lotus.create_query(%{
        name: "Error Logs",
        description: "Elasticsearch error and warning logs",
        data_source: "elasticsearch",
        statement:
          ~s|{"query": {"bool": {"filter": [{"terms": {"level": ["error", "warn"]}}]}}, "sort": [{"timestamp": {"order": "desc"}}]}|
      })
  end

  # Create sample dashboards
  {:ok, overview_dashboard} =
    Lotus.create_dashboard(%{
      name: "Business Overview",
      description: "Key business metrics at a glance"
    })

  # Add cards to overview dashboard
  {:ok, _} =
    Lotus.create_dashboard_card(overview_dashboard, %{
      card_type: :heading,
      title: "Welcome",
      content: %{"text" => "Business Overview Dashboard"},
      position: 0,
      layout: %{x: 0, y: 0, w: 12, h: 2}
    })

  {:ok, users_card} =
    Lotus.create_dashboard_card(overview_dashboard, %{
      card_type: :query,
      title: "Users",
      query_id: users_query.id,
      position: 1,
      layout: %{x: 0, y: 2, w: 6, h: 4}
    })

  {:ok, _} =
    Lotus.create_dashboard_card(overview_dashboard, %{
      card_type: :query,
      title: "Orders by Status",
      query_id: orders_query.id,
      position: 2,
      layout: %{x: 6, y: 2, w: 6, h: 4},
      visualization_config: %{"chart_type" => "bar", "x_field" => "status", "y_field" => "total"}
    })

  {:ok, _} =
    Lotus.create_dashboard_card(overview_dashboard, %{
      card_type: :text,
      title: "Notes",
      content: %{
        "text" => "This dashboard shows key business metrics including users, orders, and posts."
      },
      position: 3,
      layout: %{x: 0, y: 6, w: 4, h: 3}
    })

  {:ok, posts_card} =
    Lotus.create_dashboard_card(overview_dashboard, %{
      card_type: :query,
      title: "Recent Posts",
      query_id: user_posts_query.id,
      position: 4,
      layout: %{x: 4, y: 6, w: 8, h: 4}
    })

  # Add a "Name" filter to the Business Overview dashboard
  {:ok, name_filter} =
    Lotus.create_dashboard_filter(overview_dashboard, %{
      name: "name",
      label: "Name",
      filter_type: :text,
      widget: :input,
      position: 0
    })

  # Map the filter to the "name" variable on Users card and "author" variable on Recent Posts card
  Lotus.create_filter_mapping(users_card, name_filter, "name")
  Lotus.create_filter_mapping(posts_card, name_filter, "author")

  # Create second dashboard
  {:ok, reporting_dashboard} =
    Lotus.create_dashboard(%{
      name: "Reporting Dashboard",
      description: "Financial reports from the reporting schema"
    })

  {:ok, _} =
    Lotus.create_dashboard_card(reporting_dashboard, %{
      card_type: :query,
      title: "Invoice Summary",
      query_id: invoices_query.id,
      position: 0,
      layout: %{x: 0, y: 0, w: 6, h: 4},
      visualization_config: %{"chart_type" => "pie", "x_field" => "status", "y_field" => "total"}
    })

  {:ok, _} =
    Lotus.create_dashboard_card(reporting_dashboard, %{
      card_type: :link,
      title: "Documentation",
      content: %{"url" => "https://github.com/elixir-lotus/lotus"},
      position: 1,
      layout: %{x: 6, y: 0, w: 6, h: 2}
    })

  IO.puts("✅ Database setup complete!")
  IO.puts("🐘 PostgreSQL (localhost:2346): public & reporting schemas")
  if on?.("mysql"), do: IO.puts("🐬 MySQL (localhost:3308): products & sales tables")
  if on?.("sqlite"), do: IO.puts("🪶 SQLite (priv/lotus_web_dev.db): products & sales tables")
  if on?.("clickhouse"), do: IO.puts("🏠 ClickHouse (localhost:9123): events & page_views tables")
  if on?.("elasticsearch"), do: IO.puts("🔍 OpenSearch (localhost:9209): dev_logs index")
  IO.puts("📊 Seeded queries and 2 dashboards")
  IO.puts("🌐 Web server running on http://localhost:#{port}/lotus")
  IO.puts("🔧 Adminer available at http://localhost:8087")

  Process.sleep(:infinity)
end)
