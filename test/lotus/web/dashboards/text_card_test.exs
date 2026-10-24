defmodule Lotus.Web.Dashboards.TextCardTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Dashboards.TextCard

  doctest TextCard

  describe "fill/2" do
    test "writes a filter's value as text, never as Markdown" do
      assert TextCard.fill("In {{region}}", %{"region" => "*North* [x](y)"}) ==
               ~S"In \*North\* \[x\](y)"
    end

    test "writes a date token in words, and a dash for no value" do
      values = %{"period" => "last_30_days", "region" => ""}

      assert TextCard.fill("{{ period }}, {{region}}", values) == "Last 30 days, —"
    end

    test "leaves a name that is no filter as it is" do
      assert TextCard.fill("{{nope}}", %{"region" => "North"}) == "{{nope}}"
    end
  end

  test "a heading card from before is a text card with a heading" do
    card = %{card_type: :heading, title: "Welcome", content: %{"text" => "Sales "}}

    assert %{card_type: :text, title: nil, content: %{"text" => "## Sales"}} =
             TextCard.as_text(card)

    assert TextCard.heading?(%{title: nil, content: %{"text" => "## Sales"}})
    refute TextCard.heading?(%{title: nil, content: %{"text" => "## Sales\n\nMore"}})
  end
end
