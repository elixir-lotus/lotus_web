defmodule Lotus.Web.AssetsTest do
  use Lotus.Web.Case, async: true

  alias Lotus.Web.Assets

  describe "GET /css-:md5" do
    test "serves the embedded stylesheet with immutable caching" do
      conn = get(build_conn(), "/lotus/css-#{Assets.current_hash(:css)}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "returns 404 without caching for a hash this build did not produce" do
      conn = get(build_conn(), "/lotus/css-deadbeef")

      assert conn.status == 404
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "GET /js-:md5" do
    test "serves the embedded JS bundle with immutable caching" do
      conn = get(build_conn(), "/lotus/js-#{Assets.current_hash(:js)}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/javascript"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "returns 404 for a stale hash" do
      conn = get(build_conn(), "/lotus/js-#{Assets.current_hash(:css)}")

      assert conn.status == 404
    end
  end

  describe "content negotiation" do
    test "serves the JS gzipped when the client accepts it, and varies on accept-encoding" do
      identity = get(build_conn(), "/lotus/js-#{Assets.current_hash(:js)}")

      conn =
        build_conn()
        |> put_req_header("accept-encoding", "gzip, deflate, br")
        |> get("/lotus/js-#{Assets.current_hash(:js)}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == ["gzip"]
      assert get_resp_header(conn, "vary") == ["accept-encoding"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert :zlib.gunzip(conn.resp_body) == identity.resp_body
      assert byte_size(conn.resp_body) < byte_size(identity.resp_body)
    end

    test "serves the CSS gzipped when the client accepts it" do
      conn =
        build_conn()
        |> put_req_header("accept-encoding", "gzip")
        |> get("/lotus/css-#{Assets.current_hash(:css)}")

      assert get_resp_header(conn, "content-encoding") == ["gzip"]

      assert :zlib.gunzip(conn.resp_body) ==
               get(build_conn(), "/lotus/css-#{Assets.current_hash(:css)}").resp_body
    end

    test "serves identity when the client does not accept gzip, still varying on accept-encoding" do
      conn =
        build_conn()
        |> put_req_header("accept-encoding", "br")
        |> get("/lotus/css-#{Assets.current_hash(:css)}")

      assert get_resp_header(conn, "content-encoding") == []
      assert get_resp_header(conn, "vary") == ["accept-encoding"]
    end
  end

  describe "stale?/1" do
    test "is true when a tracked Lotus asset URL carries a hash this build did not produce" do
      assert Assets.stale?(["http://example.com/lotus/css-#{String.duplicate("0", 32)}"])
      assert Assets.stale?(["/lotus/js-#{String.duplicate("f", 32)}?vsn=d"])
    end

    test "is false for the current hashes, for foreign URLs, and for missing params" do
      refute Assets.stale?([
               "http://example.com/lotus/css-#{Assets.current_hash(:css)}",
               "http://example.com/lotus/js-#{Assets.current_hash(:js)}",
               "http://example.com/assets/app-123abc.js"
             ])

      refute Assets.stale?([])
      refute Assets.stale?(nil)
    end
  end

  describe "root layout" do
    test "references the hashed asset paths under the mount prefix" do
      doc = build_conn() |> get("/lotus") |> html_response(200) |> Floki.parse_document!()

      assert [link] = Floki.find(doc, "link[rel=stylesheet]")
      assert Floki.attribute(link, "href") == ["/lotus/css-#{Assets.current_hash(:css)}"]

      assert ["/lotus/js-#{Assets.current_hash(:js)}"] ==
               doc |> Floki.find("script[defer]") |> Floki.attribute("src")
    end
  end

  describe "connected mount after a deploy" do
    test "redirects to the current URL when the client loaded a previous bundle" do
      conn =
        build_conn()
        |> put_connect_params(%{
          "_track_static" => [
            "http://www.example.com/lotus/css-#{String.duplicate("0", 32)}",
            "http://www.example.com/lotus/js-#{Assets.current_hash(:js)}"
          ]
        })

      assert {:error, {:redirect, %{to: "/lotus/queries?tab=all"}}} =
               live(conn, "/lotus/queries?tab=all")
    end

    test "mounts normally when the tracked bundle is current" do
      conn =
        build_conn()
        |> put_connect_params(%{
          "_track_static" => [
            "http://www.example.com/lotus/css-#{Assets.current_hash(:css)}",
            "http://www.example.com/lotus/js-#{Assets.current_hash(:js)}"
          ]
        })

      assert {:ok, _view, _html} = live(conn, "/lotus")
    end
  end
end
