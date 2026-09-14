defmodule Lotus.Web.AuthorizationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lotus.Web.Authorization

  # Records every call in the test process that made it, and allows only
  # `:query` on the "reporting" source.
  defmodule RecordingResolver do
    @behaviour Lotus.Web.Resolver

    @impl true
    def resolve_access(_user), do: :all

    @impl true
    def authorize(user, action, resource) do
      send(self(), {:authorize, user, action, resource})

      case {action, resource} do
        {:query, "reporting"} -> :allow
        _ -> {:deny, "no #{action}"}
      end
    end
  end

  defmodule AccessOnlyResolver do
    @behaviour Lotus.Web.Resolver

    @impl true
    def resolve_access(_user), do: :read_only
  end

  defmodule BrokenResolver do
    @behaviour Lotus.Web.Resolver

    @impl true
    def authorize(_user, _action, _resource), do: true
  end

  @user %{id: 1}

  describe "default_decision/2" do
    test ":all allows every action" do
      for action <- Authorization.actions() do
        assert Authorization.default_decision(:all, action) == :allow
      end
    end

    test ":read_only allows querying, exporting and viewing dashboards only" do
      allowed = [:query, :export, :view_dashboard]

      for action <- Authorization.actions() do
        decision = Authorization.default_decision(:read_only, action)

        if action in allowed do
          assert decision == :allow, "expected :read_only to allow #{action}"
        else
          assert {:deny, reason} = decision, "expected :read_only to deny #{action}"
          assert is_binary(reason)
        end
      end
    end

    test ":forbidden denies every action" do
      for access <- [:forbidden, {:forbidden, "/login"}], action <- Authorization.actions() do
        assert {:deny, _} = Authorization.default_decision(access, action)
      end
    end

    test "rejects an action outside the vocabulary" do
      # Through apply/3, so the type checker does not flag the bad call at compile time.
      assert_raise FunctionClauseError, fn ->
        apply(Authorization, :default_decision, [:all, :drop_table])
      end
    end
  end

  describe "authorize/3" do
    test "asks the resolver with the user, the action and the resource" do
      assigns = %{resolver: RecordingResolver, user: @user, access: :all}

      assert Authorization.authorize(assigns, :query, "reporting") == :allow
      assert_received {:authorize, @user, :query, "reporting"}

      assert Authorization.authorize(assigns, :export, "reporting") == {:deny, "no export"}
      assert_received {:authorize, @user, :export, "reporting"}
    end

    test "the resolver wins over the access level" do
      assigns = %{resolver: RecordingResolver, user: @user, access: :all}

      assert {:deny, _} = Authorization.authorize(assigns, :create_query)
    end

    test "derives the decision from :access when the resolver has no authorize/3" do
      assigns = %{resolver: AccessOnlyResolver, user: @user, access: :read_only}

      assert Authorization.authorize(assigns, :query, "reporting") == :allow
      assert {:deny, _} = Authorization.authorize(assigns, :delete_query, %{})
    end

    test "with no resolver, derives the decision from :access" do
      assert Authorization.authorize(%{access: :all}, :manage_cache) == :allow
      assert {:deny, _} = Authorization.authorize(%{access: :read_only}, :manage_cache)
    end

    test "with no :access assign, keeps full access as the dashboard did before" do
      assert Authorization.authorize(%{}, :delete_query, %{}) == :allow
    end

    test "never asks the host for a public dashboard" do
      assigns = %{resolver: RecordingResolver, user: nil, access: :all, public_view: true}

      assert Authorization.authorize(assigns, :view_dashboard, %{}) == :allow
      assert {:deny, _} = Authorization.authorize(assigns, :manage_dashboard, %{})
      refute_received {:authorize, _, _, _}
    end

    test "denies when the resolver returns something other than a decision" do
      assigns = %{resolver: BrokenResolver, user: @user}

      log =
        capture_log(fn ->
          assert {:deny, _} = Authorization.authorize(assigns, :query, "reporting")
        end)

      assert log =~ "BrokenResolver.authorize/3 returned true"
    end

    test "ignores the :permissions cache and always asks" do
      assigns = %{
        resolver: RecordingResolver,
        user: @user,
        permissions: %{create_query: true}
      }

      assert {:deny, _} = Authorization.authorize(assigns, :create_query)
      assert_received {:authorize, @user, :create_query, nil}
    end
  end

  describe "allowed?/3" do
    test "reads the :permissions cache for an action without a resource" do
      assigns = %{resolver: RecordingResolver, user: @user, permissions: %{create_query: true}}

      assert Authorization.allowed?(assigns, :create_query)
      refute_received {:authorize, _, _, _}
    end

    test "asks the resolver for an action with a resource" do
      assigns = %{resolver: RecordingResolver, user: @user, permissions: %{create_query: true}}

      assert Authorization.allowed?(assigns, :query, "reporting")
      refute Authorization.allowed?(assigns, :query, "billing")
    end
  end

  describe "permissions/1" do
    test "decides every action that takes no resource" do
      assigns = %{resolver: AccessOnlyResolver, user: @user, access: :read_only}

      assert Authorization.permissions(assigns) == %{
               create_query: false,
               manage_dashboard: false,
               manage_source: false,
               manage_cache: false
             }
    end

    test "does not read an older cache" do
      assigns = %{access: :all, permissions: %{create_query: false}}

      assert %{create_query: true} = Authorization.permissions(assigns)
    end
  end

  describe "decide/5" do
    test "works without socket assigns, as a controller needs" do
      assert {:deny, "no export"} =
               Authorization.decide(RecordingResolver, @user, :all, :export, "reporting")

      assert Authorization.decide(nil, nil, :read_only, :export, "reporting") == :allow
    end
  end
end
