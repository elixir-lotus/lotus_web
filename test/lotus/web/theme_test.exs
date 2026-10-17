defmodule Lotus.Web.ThemeTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Theme

  test "listing the built-in themes" do
    assert Theme.names() == [:lotus, :sumi]
  end

  describe "valid_colors?/1" do
    test "accepting hex colours for known tokens, as strings or atoms" do
      assert Theme.valid_colors?(%{})
      assert Theme.valid_colors?(%{"pink-600" => "#0ea5e9", "canvas" => "#fff"})
      assert Theme.valid_colors?(%{"gray-950": "#0A0A0B"})
    end

    test "refusing unknown tokens and values that are not hex colours" do
      refute Theme.valid_colors?(%{"brand" => "#0ea5e9"})
      refute Theme.valid_colors?(%{"pink-600" => "rgb(14 165 233)"})
      refute Theme.valid_colors?(%{"pink-600" => "#0ea5e9;}"})
      refute Theme.valid_colors?(%{"pink-600" => nil})
    end
  end

  describe "css/1" do
    test "rendering the overrides as RGB channels, over every theme" do
      assert Theme.css(%{"pink-600" => "#0ea5e9", "canvas" => "#fff"}) ==
               ":root[data-lotus-theme] { --lotus-canvas: 255 255 255; --lotus-pink-600: 14 165 233; }"
    end

    test "rendering nothing without overrides" do
      assert Theme.css(%{}) == nil
      assert Theme.css(nil) == nil
    end
  end
end
