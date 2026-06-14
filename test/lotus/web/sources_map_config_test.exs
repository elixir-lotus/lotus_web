defmodule Lotus.Web.SourcesMapConfigTest do
  # async: false because this mutates the global :lotus_web :include_views
  # application env, which SourcesMap.build/1 reads as its default.
  use Lotus.Web.Case, async: false

  alias Lotus.Web.SourcesMap

  setup do
    original = Application.get_env(:lotus_web, :include_views)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:lotus_web, :include_views)
        value -> Application.put_env(:lotus_web, :include_views, value)
      end
    end)

    :ok
  end

  defp public_tables(sources_map) do
    sources_map
    |> SourcesMap.get_database("public")
    |> Map.fetch!(:schemas)
    |> Enum.find(&(&1.name == "public"))
    |> Map.fetch!(:tables)
  end

  test "build/0 includes views when :lotus_web :include_views config is true" do
    Application.put_env(:lotus_web, :include_views, true)

    assert "active_test_users" in public_tables(SourcesMap.build())
  end

  test "an explicit include_views option overrides the config" do
    Application.put_env(:lotus_web, :include_views, true)

    refute "active_test_users" in public_tables(SourcesMap.build(include_views: false))
  end
end
