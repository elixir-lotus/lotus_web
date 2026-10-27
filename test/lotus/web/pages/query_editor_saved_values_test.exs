defmodule Lotus.Web.Pages.QueryEditorSavedValuesTest do
  use Lotus.Web.Case

  import Phoenix.LiveViewTest

  setup do
    create_test_users()
    :ok
  end

  # A new query with a {{name}} dropdown of three names, saved.
  defp save_new_query_with_dropdown do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")

    live
    |> with_target("#query-editor-page")
    |> render_hook("editor_content_changed", %{
      "statement" => "SELECT name, email FROM test_users WHERE name = {{name}}"
    })

    live
    |> with_target("#query-editor-page")
    |> render_hook("variables_detected", %{"variables" => ["name"]})

    live |> element("#variable-settings-btn") |> render_click()

    live
    |> element("#variable-settings-form")
    |> render_change(%{"query" => %{"variables" => %{"0" => %{"widget" => "select"}}}})

    live |> element(~s([phx-click="open_dropdown_options_modal"])) |> render_click()

    live
    |> element("#dropdown-options-modal textarea[name=options]")
    |> render_keyup(%{"value" => "Alice\nBob\nCharlie"})

    live |> element("#dropdown-options-modal button", "Done") |> render_click()

    live
    |> element(~s(form[phx-submit="save_query"]))
    |> render_submit(%{"query" => %{"name" => "Users by name", "description" => ""}})

    live
  end

  test "a value chosen right after saving a new query is the one the query runs with" do
    live = save_new_query_with_dropdown()

    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_change(%{"variables" => %{"name" => "Bob"}})

    # The "Query saved" flash clears itself, which renders the dashboard again.
    render_hook(live, "lv:clear-flash", %{"key" => "info"})

    live
    |> element(~s(form[phx-submit="run_query"]))
    |> render_submit(%{})

    html = render_async(live)
    assert html =~ "bob@test.com"
    refute html =~ "alice@test.com"
  end
end
