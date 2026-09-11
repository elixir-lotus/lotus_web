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

  describe "root layout" do
    test "references the hashed asset paths under the mount prefix" do
      doc = build_conn() |> get("/lotus") |> html_response(200) |> Floki.parse_document!()

      assert [link] = Floki.find(doc, "link[rel=stylesheet]")
      assert Floki.attribute(link, "href") == ["/lotus/css-#{Assets.current_hash(:css)}"]

      assert ["/lotus/js-#{Assets.current_hash(:js)}"] ==
               doc |> Floki.find("script[defer]") |> Floki.attribute("src")
    end
  end
end
