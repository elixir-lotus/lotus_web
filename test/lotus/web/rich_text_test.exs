defmodule Lotus.Web.RichTextTest do
  use ExUnit.Case, async: true

  alias Kotoba.Content
  alias Lotus.Web.RichText

  describe "features/2" do
    test "a description has inline formats only" do
      assert RichText.features(:description, nil) ==
               [:bold, :italic, :strikethrough, :inline_code, :links]
    end

    test "a text card keeps a table, an image or a footnote it already has" do
      refute :tables in RichText.features(:text_card, "Text")
      assert :tables in RichText.features(:text_card, "| a |\n|---|\n| 1 |")
    end
  end

  describe "to_markdown/1" do
    test "writes the editor's document as Markdown" do
      doc = Content.from_markdown("# Title\n\n**bold** and [a link](https://a.b)").doc
      assert RichText.to_markdown(doc) == "# Title\n\n**bold** and [a link](https://a.b)"
    end

    test "keeps Markdown as it is, and an empty document is empty" do
      assert RichText.to_markdown("**x**") == "**x**"
      assert RichText.to_markdown(Content.from_markdown("").doc) == ""
      assert RichText.to_markdown(nil) == ""
    end
  end

  describe "editor_value/2" do
    test "loads Markdown into the editor with the features given" do
      content = RichText.editor_value("# Title", [:bold])
      assert content.html == "<p>Title</p>"
    end
  end

  describe "plain_text/1" do
    test "is the text of the Markdown on one line" do
      assert RichText.plain_text("# Sales\n\nBy **region**") == "Sales By region"
      assert RichText.plain_text("") == nil
      assert RichText.plain_text(nil) == nil
    end
  end
end
