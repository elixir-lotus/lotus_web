defmodule Lotus.Web.Markdown do
  @moduledoc """
  Safe markdown rendering helpers.

  Renders markdown to HTML with MDEx using its safe defaults (`unsafe: false`),
  so untrusted input (AI responses, user-entered dashboard text) cannot inject
  `<script>` tags, inline event handlers, or `javascript:` URLs — embedded raw
  HTML is dropped rather than emitted, so no separate sanitizer is needed.

  Images don't render: a Markdown image becomes a link to its URL. An image
  would load in every viewer's browser, public dashboards included, so one
  from another host could track who looked and carry data out in its URL.
  """

  # GitHub Flavored Markdown, which the rich text editor writes.
  @options [
    extension: [strikethrough: true, table: true, autolink: true, tasklist: true, footnotes: true]
  ]

  @doc """
  Renders a markdown string to safe HTML, wrapped in `Phoenix.HTML.raw/1`.

  Returns an empty string for non-binary input, and the original text if MDEx
  fails to parse it.
  """
  def to_safe_html(text) when is_binary(text) do
    with {:ok, document} <- MDEx.parse_document(text, @options),
         {:ok, html} <- document |> link_images() |> MDEx.to_html(@options) do
      Phoenix.HTML.raw(html)
    else
      {:error, _} -> text
    end
  end

  def to_safe_html(_), do: ""

  # A link with the image's alt text, or its URL when there is none.
  defp link_images(document) do
    MDEx.traverse_and_update(document, fn
      %MDEx.Image{url: url, title: title, nodes: nodes} ->
        %MDEx.Link{
          url: url,
          title: title,
          nodes: if(nodes == [], do: [%MDEx.Text{literal: url}], else: nodes)
        }

      node ->
        node
    end)
  end
end
