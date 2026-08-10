defmodule Lotus.Web.Controllers.AssetsTest do
  use Lotus.Web.Case, async: true

  alias Lotus.Web.Assets

  describe "GET /css-:md5" do
    test "serves the embedded stylesheet with immutable caching" do
      conn = get(build_conn(), "/lotus/css-#{Assets.current_hash(:css)}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end
  end

  describe "GET /js-:md5" do
    test "serves the embedded JS bundle with immutable caching" do
      conn = get(build_conn(), "/lotus/js-#{Assets.current_hash(:js)}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/javascript"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end
  end

  describe "root layout" do
    test "references the hashed asset paths" do
      html = html_response(get(build_conn(), "/lotus"), 200)

      assert [link] = html |> Floki.parse_document!() |> Floki.find("link[rel=stylesheet]")
      assert Floki.attribute(link, "href") == ["/lotus/css-#{Assets.current_hash(:css)}"]

      assert [src] =
               html
               |> Floki.parse_document!()
               |> Floki.find("script[defer]")
               |> Floki.attribute("src")

      assert src == "/lotus/js-#{Assets.current_hash(:js)}"
    end
  end
end
