defmodule Lotus.Web.MarkdownTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Markdown

  describe "to_safe_html/1" do
    test "renders markdown into a safe HTML tuple" do
      html = Markdown.to_safe_html("**bold text**") |> Phoenix.HTML.safe_to_string()

      assert html =~ "<strong>bold text</strong>"
    end

    test "returns empty string for empty input without wrapping it as safe" do
      assert Markdown.to_safe_html("") == ""
    end

    test "returns empty string for non-binary input" do
      assert Markdown.to_safe_html(nil) == ""
      assert Markdown.to_safe_html(%{text: "x"}) == ""
    end

    test "drops embedded raw HTML instead of rendering it" do
      html =
        "# Heading\n\n<script>alert('xss')</script>"
        |> Markdown.to_safe_html()
        |> Phoenix.HTML.safe_to_string()

      assert html =~ "<h1>Heading</h1>"
      refute html =~ "<script>"
      refute html =~ "alert('xss')"
    end

    test "neutralizes javascript: link targets" do
      html =
        "[click](javascript:alert(1))"
        |> Markdown.to_safe_html()
        |> Phoenix.HTML.safe_to_string()

      refute html =~ "javascript:"
    end
  end
end
