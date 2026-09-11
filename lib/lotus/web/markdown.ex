defmodule Lotus.Web.Markdown do
  @moduledoc """
  Safe markdown rendering helpers.

  Renders markdown to HTML with MDEx using its safe defaults (`unsafe: false`),
  so untrusted input (AI responses, user-entered dashboard text) cannot inject
  `<script>` tags, inline event handlers, or `javascript:` URLs — embedded raw
  HTML is dropped rather than emitted, so no separate sanitizer is needed.
  """

  @doc """
  Renders a markdown string to safe HTML, wrapped in `Phoenix.HTML.raw/1`.

  Returns an empty string for non-binary input, and the original text if MDEx
  fails to parse it.
  """
  def to_safe_html(text) when is_binary(text) do
    case MDEx.to_html(text) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      {:error, _} -> text
    end
  end

  def to_safe_html(_), do: ""
end
