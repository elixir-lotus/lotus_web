defmodule Lotus.Web.Assets do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @static_path Application.app_dir(:lotus_web, ["priv", "static"])

  @external_resource css_path = Path.join(@static_path, "css/app.css")

  @css File.read!(css_path)

  phoenix_js_paths =
    for app <- ~w(phoenix phoenix_html phoenix_live_view)a do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  @external_resource js_path = Path.join(@static_path, "app.js")

  @js """
  #{for path <- phoenix_js_paths, do: path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")}
  #{File.read!(js_path)}
  """

  @impl Plug
  def init(asset), do: asset

  @impl Plug
  def call(conn, :css) do
    serve_asset(conn, :css, @css, "text/css")
  end

  def call(conn, :js) do
    # Plug.CSRFProtection rejects non-XHR GET responses with a JavaScript
    # content type as a cross-origin script read. This bundle is public, so
    # opt out; the CSS response needs no such exception.
    conn
    |> put_private(:plug_skip_csrf_protection, true)
    |> serve_asset(:js, @js, "text/javascript")
  end

  # The URL carries the content hash and the response is cached as immutable,
  # so only the hash this build produced may be served under it. A stale hash
  # (an old node during a rolling deploy, or a bookmarked URL) gets a 404
  # rather than poisoning caches with the wrong bundle for a year.
  defp serve_asset(%{path_params: %{"md5" => md5}} = conn, asset, contents, content_type) do
    if md5 == current_hash(asset) do
      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_resp(200, contents)
      |> halt()
    else
      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(404, "")
      |> halt()
    end
  end

  for {key, val} <- [css: @css, js: @js] do
    md5 = Base.encode16(:crypto.hash(:md5, val), case: :lower)

    def current_hash(unquote(key)), do: unquote(md5)
  end
end
