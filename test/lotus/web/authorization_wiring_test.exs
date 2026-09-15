defmodule Lotus.Web.AuthorizationWiringTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lotus.Web.Authorization

  setup do
    Application.put_env(:lotus_web, :strict_actor, false)
    on_exit(fn -> Application.put_env(:lotus_web, :strict_actor, true) end)
  end

  describe "without strict_actor, assigns with no :resolver or :access key" do
    test "decide with :read_only access and log the error" do
      log =
        capture_log(fn ->
          assert Authorization.authorize(%{}, :query, "reporting") == :allow
          assert {:deny, _} = Authorization.authorize(%{}, :delete_query, %{})
          assert {:deny, _} = Authorization.authorize(%{access: :all}, :manage_cache)
          assert {:deny, _} = Authorization.authorize(%{resolver: nil}, :manage_cache)
          refute Authorization.allowed?(%{}, :create_query)
        end)

      assert log =~ "no :resolver or :access key"
      assert log =~ "Deciding with :read_only access."
    end

    test "leave correctly wired assigns alone" do
      log =
        capture_log(fn ->
          assert Authorization.authorize(%{resolver: nil, access: :all}, :manage_cache) == :allow
        end)

      refute log =~ "no :resolver or :access key"
    end
  end
end
