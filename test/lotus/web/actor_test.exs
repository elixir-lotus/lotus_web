defmodule Lotus.Web.ActorTest do
  use ExUnit.Case, async: true

  alias Lotus.Web.Actor
  alias Lotus.Web.Resolver

  defmodule ScopedResolver do
    @behaviour Resolver

    def resolve_user(_conn), do: %{id: 7, tenant_id: "acme"}
    def resolve_context(%{id: id}), do: %{user_id: id}
    def resolve_scope(%{tenant_id: tenant_id}), do: %{tenant_id: tenant_id}
  end

  defmodule PlainResolver do
    @behaviour Resolver

    def resolve_user(_conn), do: %{id: 7}
  end

  describe "resolve/2" do
    test "asks the resolver for both halves of the actor" do
      user = %{id: 7, tenant_id: "acme"}

      assert Actor.resolve(ScopedResolver, user) == {%{user_id: 7}, %{tenant_id: "acme"}}
    end

    test "falls back to nil for a resolver that declares neither callback" do
      assert Actor.resolve(PlainResolver, %{id: 7}) == {nil, nil}
    end

    test "a dashboard mounted without a resolver has no actor" do
      assert Actor.resolve(nil, nil) == {nil, nil}
    end
  end

  describe "opts/1" do
    test "builds the core options from socket assigns" do
      assigns = %{context: %{user_id: 7}, scope: %{tenant_id: "acme"}}

      assert Actor.opts(assigns) == [context: %{user_id: 7}, scope: %{tenant_id: "acme"}]
    end

    test "leaves out the halves the resolver did not provide" do
      assert Actor.opts(%{context: %{user_id: 7}, scope: nil}) == [context: %{user_id: 7}]

      assert Actor.opts(%{context: nil, scope: %{tenant_id: "acme"}}) == [
               scope: %{tenant_id: "acme"}
             ]
    end

    test "an unscoped dashboard calls core with no actor options at all" do
      assert Actor.opts(%{context: nil, scope: nil}) == []
      assert Actor.opts({nil, nil}) == []
    end

    test "assigns with no :context key at all mean the actor never arrived" do
      # A LiveComponent holds only what its parent passes. An unscoped
      # dashboard has `context: nil`; a component nobody passed the actor to
      # has no `:context` key. The two must not look the same.
      error = assert_raise ArgumentError, fn -> Actor.opts(%{}) end

      assert error.message =~ "no :context key"
      assert error.message =~ "actor={@actor}"
    end

    test "the check is off unless a host asks for it" do
      Application.put_env(:lotus_web, :strict_actor, false)
      on_exit(fn -> Application.put_env(:lotus_web, :strict_actor, true) end)

      assert Actor.opts(%{}) == []
    end

    test "an explicit actor tuple skips the check" do
      assert Actor.opts({nil, nil}) == []
      assert Actor.opts({%{user_id: 7}, nil}) == [context: %{user_id: 7}]
    end
  end

  describe "merge/2" do
    test "adds the actor to an existing option list" do
      opts = Actor.merge([repo: "postgres"], %{context: :ctx, scope: :sco})

      assert Keyword.equal?(opts, repo: "postgres", context: :ctx, scope: :sco)
    end

    test "an explicit option wins over the actor" do
      opts = Actor.merge([context: :explicit], %{context: :from_assigns, scope: nil})

      assert opts[:context] == :explicit
    end

    test "leaves the option list untouched without an actor" do
      assert Actor.merge([repo: "postgres"], %{context: nil, scope: nil}) == [repo: "postgres"]
    end
  end
end
