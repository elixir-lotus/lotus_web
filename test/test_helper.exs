Application.ensure_all_started(:postgrex)

Application.put_env(:lotus_web, Lotus.Web.TestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 2346,
  database: "lotus_web_test",
  pool: Ecto.Adapters.SQL.Sandbox
)

Application.put_env(:lotus_web, Lotus.Web.ReportingTestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 2346,
  database: "lotus_web_test",
  parameters: [search_path: "reporting"],
  pool: Ecto.Adapters.SQL.Sandbox
)

Application.put_env(:lotus, :storage_repo, Lotus.Web.TestRepo)

Application.put_env(:lotus, :data_sources, %{
  "public" => Lotus.Web.TestRepo,
  "reporting" => Lotus.Web.ReportingTestRepo
})

Application.put_env(:lotus, :default_source, "public")

# Lotus caches its validated config in :persistent_term at boot, so any
# Application.put_env calls above need an explicit reload to take effect.
Lotus.Config.reload!()

Application.put_env(:lotus_web, Lotus.Web.Endpoint,
  check_origin: false,
  http: [port: 4002],
  live_view: [signing_salt: "aWVuxqSi0zkb79Wkjuey3R1OAxEaBHhZ"],
  render_errors: [formats: [html: Lotus.Web.ErrorHTML], layout: false],
  secret_key_base: "yIWyfLRyoZo3dC2Y0rKjYcusy3g2p+mhN0sLTFOxkn/pY8yCq+e8b+Jhe9IndMGO",
  server: false,
  url: [host: "localhost"]
)

defmodule Lotus.Web.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

# A resolver that gives the dashboard an actor, so tests can assert that
# :context and :scope reach Lotus core from a UI-driven call.
defmodule Lotus.Web.Test.ScopedResolver do
  @behaviour Lotus.Web.Resolver

  def resolve_user(_conn), do: %{id: 42, tenant_id: "acme"}
  def resolve_context(%{id: id}), do: %{user_id: id}
  def resolve_scope(%{tenant_id: tenant_id}), do: %{tenant_id: tenant_id}
end

# A resolver that implements authorize/3 and allows only viewing dashboards and
# running queries on sources other than "reporting", so tests can assert that
# every other control is hidden and every other handler refuses.
defmodule Lotus.Web.Test.RestrictedResolver do
  @behaviour Lotus.Web.Resolver

  def resolve_user(_conn), do: %{id: 7}
  def resolve_access(_user), do: :all

  def authorize(_user, :query, "reporting"), do: {:deny, "Restricted: query"}
  def authorize(_user, action, _resource) when action in [:query, :view_dashboard], do: :allow
  def authorize(_user, action, _resource), do: {:deny, "Restricted: #{action}"}
end

# A resolver with only resolve_access/1, so tests can assert the decision that
# derives from :read_only.
defmodule Lotus.Web.Test.ReadOnlyResolver do
  @behaviour Lotus.Web.Resolver

  def resolve_user(_conn), do: %{id: 8}
  def resolve_access(_user), do: :read_only
end

defmodule Lotus.Web.Test.Router do
  use Phoenix.Router

  import Lotus.Web.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_flash)
  end

  scope "/", ThisWontBeUsed, as: :this_wont_be_used do
    pipe_through(:browser)

    lotus_dashboard("/lotus", features: [:timeout_options])

    lotus_dashboard("/scoped",
      as: :scoped_dashboard,
      resolver: Lotus.Web.Test.ScopedResolver
    )

    lotus_dashboard("/restricted",
      as: :restricted_dashboard,
      resolver: Lotus.Web.Test.RestrictedResolver
    )

    lotus_dashboard("/read_only",
      as: :read_only_dashboard,
      resolver: Lotus.Web.Test.ReadOnlyResolver
    )
  end
end

defmodule Lotus.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :lotus_web

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session,
    store: :cookie,
    key: "_lotus_web_key",
    signing_salt: "LgTvNDDF"
  )

  plug(Lotus.Web.Test.Router)
end

_ = Lotus.Web.TestRepo.__adapter__().storage_up(Lotus.Web.TestRepo.config())

{:ok, _} = Lotus.Web.TestRepo.start_link()
{:ok, _} = Lotus.Web.ReportingTestRepo.start_link()
{:ok, _} = Lotus.Web.Endpoint.start_link()

migrations_path = Path.join([File.cwd!(), "test/support/postgres/migrations"])
_ = Ecto.Migrator.run(Lotus.Web.TestRepo, migrations_path, :up, all: true, log: false)

Ecto.Adapters.SQL.Sandbox.mode(Lotus.Web.TestRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Lotus.Web.ReportingTestRepo, :manual)

ExUnit.start(assert_receive_timeout: 500, refute_receive_timeout: 50, exclude: [:skip])
