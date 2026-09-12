defmodule Lotus.Web.Assets do
  @moduledoc """
  Serves the dashboard's CSS and JavaScript bundle.

  `Lotus.Web.Router.lotus_dashboard/2` mounts this plug at
  `<prefix>/css-<hash>` and `<prefix>/js-<hash>`, where `<hash>` is the MD5 of
  the compiled asset. A host never calls it: the URLs come from the layout
  through `lotus_asset_path/3`.

  The bundle is read and gzipped at compile time, so a response costs no disk
  read. Because each URL names the build it came from, the plug answers with
  `cache-control: public, max-age=31536000, immutable`, and answers a hash
  this build did not produce with a 404 and `cache-control: no-store`.
  """

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

  # Compressed once at compile time. Each literal is referenced from exactly
  # one function body below, so the .beam carries one copy of each variant.
  @css_gz :zlib.gzip(@css)
  @js_gz :zlib.gzip(@js)

  @impl Plug
  def init(asset), do: asset

  @impl Plug
  def call(conn, :css) do
    serve_asset(conn, :css, "text/css")
  end

  def call(conn, :js) do
    # Plug.CSRFProtection rejects non-XHR GET responses with a JavaScript
    # content type as a cross-origin script read. This bundle is public, so
    # opt out; the CSS response needs no such exception.
    conn
    |> put_private(:plug_skip_csrf_protection, true)
    |> serve_asset(:js, "text/javascript")
  end

  @doc """
  Whether any of the asset URLs a client is tracking belongs to a previous
  build of this bundle.

  `tracked` is the `_track_static` list the LiveView client sends on join:
  the URLs of every `phx-track-static` tag on the page. Only URLs shaped like
  Lotus's own asset routes (`.../css-<hash>` or `.../js-<hash>`) are
  considered; the host application's assets are ignored. The dashboard
  LiveView uses it to force a full reload after a deploy, since
  `Phoenix.LiveView.static_changed?/1` only knows the host's static manifest.
  """
  @spec stale?(term()) :: boolean()
  def stale?(tracked) when is_list(tracked) do
    Enum.any?(tracked, fn
      url when is_binary(url) ->
        path = URI.parse(url).path || ""

        case Regex.run(~r"/(css|js)-([0-9a-f]{32})\z", path) do
          [_, "css", hash] -> hash != current_hash(:css)
          [_, "js", hash] -> hash != current_hash(:js)
          nil -> false
        end

      _ ->
        false
    end)
  end

  def stale?(_), do: false

  # The URL carries the content hash and the response is cached as immutable,
  # so only the hash this build produced may be served under it. A stale hash
  # (an old node during a rolling deploy, or a bookmarked URL) gets a 404
  # rather than poisoning caches with the wrong bundle for a year.
  defp serve_asset(%{path_params: %{"md5" => md5}} = conn, asset, content_type) do
    if md5 == current_hash(asset) do
      encoding = if gzip_accepted?(conn), do: :gzip, else: :identity

      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("vary", "accept-encoding")
      |> put_content_encoding(encoding)
      |> send_resp(200, body(asset, encoding))
      |> halt()
    else
      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(404, "")
      |> halt()
    end
  end

  defp gzip_accepted?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.any?(&String.contains?(String.downcase(&1), "gzip"))
  end

  defp put_content_encoding(conn, :gzip), do: put_resp_header(conn, "content-encoding", "gzip")
  defp put_content_encoding(conn, :identity), do: conn

  defp body(:css, :identity), do: @css
  defp body(:css, :gzip), do: @css_gz
  defp body(:js, :identity), do: @js
  defp body(:js, :gzip), do: @js_gz

  for {key, val} <- [css: @css, js: @js] do
    md5 = Base.encode16(:crypto.hash(:md5, val), case: :lower)

    def current_hash(unquote(key)), do: unquote(md5)
  end
end
