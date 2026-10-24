defmodule Lotus.Web.ProTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Pro

  describe "available?/0" do
    test "returns false when Lotus.Pro.Web is not loaded" do
      refute Pro.available?()
    end
  end

  describe "extra_pages/0" do
    test "returns empty list when Pro is not available" do
      assert Pro.extra_pages() == []
    end
  end

  describe "nav_items/1" do
    test "returns empty list when Pro is not available" do
      assert Pro.nav_items(%{}) == []
    end
  end

  describe "render_slot/2" do
    test "returns nil when Pro is not available" do
      assert Pro.render_slot(:header, %{}) == nil
    end
  end

  describe "authorize_public_dashboard/2" do
    test "allows every link when Pro is not available" do
      assert Pro.authorize_public_dashboard(%{id: 1}, %{}) == :allow
    end
  end
end
