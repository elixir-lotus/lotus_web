defmodule Lotus.Web.Queries.AiAvailabilityTest do
  @moduledoc """
  The AI assistant follows `Lotus.AI.enabled?/0`, asked on every render, and
  says when AI is configured but its dependency, `req_llm`, is not
  installed. Core's application setting stands for a node without it, so
  these tests run alone.
  """
  use Lotus.Web.Case, async: false

  import ExUnit.CaptureLog

  setup do
    on_exit(fn ->
      Application.delete_env(:lotus, :ai)
      Application.delete_env(:lotus, :__ai_dependency__)
      :persistent_term.erase({Lotus.AI, :warned_missing})
      Lotus.Config.reload!()
    end)
  end

  defp ai(opts) do
    Application.put_env(:lotus, :ai, opts)
    Lotus.Config.reload!()
  end

  defp without_dependency, do: Application.put_env(:lotus, :__ai_dependency__, NoSuch.ReqLLM)

  defp open_editor do
    {:ok, live, _html} = live(build_conn(), "/lotus/queries/new")
    render_async(live)
    live
  end

  defp page(live), do: with_target(live, "#query-editor-page")

  test "AI off: no assistant, no AI in the context menu" do
    live = open_editor()

    refute has_element?(live, "#ai-assistant-btn")
    assert has_element?(live, ~s(#editor-context-menu-wrapper[data-ai-enabled="false"]))
  end

  test "AI on, with its dependency: the assistant and its form" do
    ai(enabled: true, api_key: "sk-test")
    live = open_editor()

    assert has_element?(live, ~s(#editor-context-menu-wrapper[data-ai-enabled="true"]))
    live |> element("#ai-assistant-btn") |> render_click()

    assert has_element?(live, "#ai-message-form")
    refute has_element?(live, "#ai-missing-dependency")
  end

  test "AI on, without its dependency: the assistant names it, and nothing raises" do
    ai(enabled: true, api_key: "sk-test")
    without_dependency()

    capture_log(fn ->
      live = open_editor()

      # The other AI controls are off; the assistant's button stays, to say why.
      assert has_element?(live, ~s(#editor-context-menu-wrapper[data-ai-enabled="false"]))
      live |> element("#ai-assistant-btn") |> render_click()

      assert has_element?(live, "#ai-missing-dependency")
      assert render(live) =~ "req_llm"
      refute has_element?(live, "#ai-message-form")

      # A crafted message gets the same answer, not a crash.
      render_submit(page(live), "send_ai_message", %{"message" => "count users"})
      assert render(live) =~ "req_llm"
    end)
  end

  test "AI switched on while the page is open shows at the next render" do
    live = open_editor()
    refute has_element?(live, "#ai-assistant-btn")

    ai(enabled: true, api_key: "sk-test")
    live |> element("[phx-click='toggle_schema_explorer']") |> render_click()

    assert has_element?(live, "#ai-assistant-btn")
  end
end
