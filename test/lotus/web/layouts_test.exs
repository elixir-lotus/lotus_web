defmodule Lotus.Web.LayoutsTest do
  use Lotus.Web.Case, async: true

  test "the root layout loads scripts from Lotus only" do
    html = build_conn() |> get("/lotus") |> html_response(200)

    srcs =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("script[src]")
      |> LazyHTML.attribute("src")

    assert srcs != []
    assert Enum.all?(srcs, &String.starts_with?(&1, "/lotus/"))
  end
end
