defmodule Lotus.Web.ResolverTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Resolver
  alias Lotus.Web.Test.LazyResolver

  defmodule FullImpl do
    @behaviour Resolver

    def resolve_user(_conn), do: %{id: 123}
    def resolve_access(_user), do: :read_only
  end

  defmodule PartialImpl do
    @behaviour Resolver

    def resolve_user(_conn), do: :only_user
  end

  describe "defaults" do
    test "resolve_user/1 returns nil by default" do
      assert Resolver.resolve_user(%Plug.Conn{}) == nil
    end

    test "resolve_access/1 returns :all by default" do
      assert Resolver.resolve_access(%{}) == :all
    end

    test "authorize/3 allows every action by default, as :all access does" do
      for action <- Lotus.Web.Authorization.actions() do
        assert Resolver.authorize(%{}, action, nil) == :allow
      end
    end
  end

  describe "call_with_fallback/3" do
    test "uses the implementation when function is exported" do
      assert %{id: 123} = Resolver.call_with_fallback(FullImpl, :resolve_user, [%Plug.Conn{}])
      assert :read_only == Resolver.call_with_fallback(FullImpl, :resolve_access, [%{}])
    end

    test "falls back to default when function isn't exported" do
      # PartialImpl doesn't implement resolve_access/1, so it should fallback
      assert :all == Resolver.call_with_fallback(PartialImpl, :resolve_access, [%{}])
      # But it does implement resolve_user/1
      assert :only_user == Resolver.call_with_fallback(PartialImpl, :resolve_user, [%Plug.Conn{}])
    end

    test "loads the resolver module before it decides on the fallback" do
      # The BEAM loads modules on first use, so a host resolver is often not
      # loaded yet when the dashboard mounts. It must not fail open.
      unload(LazyResolver)

      assert :read_only == Resolver.call_with_fallback(LazyResolver, :resolve_access, [%{}])

      unload(LazyResolver)

      assert %{id: 7} == Resolver.call_with_fallback(LazyResolver, :resolve_user, [%Plug.Conn{}])
    end

    test "falls back to default when the module does not exist at all" do
      assert :all == Resolver.call_with_fallback(NoSuchResolverModule, :resolve_access, [%{}])

      assert nil ==
               Resolver.call_with_fallback(NoSuchResolverModule, :resolve_user, [%Plug.Conn{}])
    end
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
    refute :erlang.module_loaded(module)
  end
end
