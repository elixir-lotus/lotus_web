defmodule Lotus.Web.RichText do
  @moduledoc """
  Rich text editing with `Kotoba`, for text that Lotus stores as Markdown:
  the content of a text card and the description of a dashboard.

  The editor loads the Markdown (`content/2`) and posts its document, which
  `to_markdown/1` writes back as Markdown, so Lotus and every app that
  writes these fields through Lotus keep Markdown.
  """

  alias Kotoba.{Content, Document, Features, Renderer}

  @text_card ~w(bold italic strikethrough inline_code links headings quotes lists check_lists
                code_blocks horizontal_rules)a
  @description ~w(bold italic strikethrough inline_code links)a

  # The features that the text of a field keeps when it already has them, so
  # that editing it loses nothing: a card written in Markdown before may
  # have a table, an image or a footnote.
  @kept_when_used ~w(tables images footnotes)a

  @doc """
  Returns the features of the editor of `kind` (`:text_card` or
  `:description`) for the Markdown it edits.
  """
  @spec features(:text_card | :description, String.t() | nil) :: [atom()]
  def features(kind, markdown) do
    base = if kind == :text_card, do: @text_card, else: @description
    used = markdown |> to_string() |> Content.from_markdown() |> used()
    Features.names!(base ++ Enum.filter(used, &(&1 in @kept_when_used or &1 in base)))
  end

  @doc """
  Returns the `Kotoba.Content` of Markdown, for the value of the editor.
  """
  @spec content(String.t() | nil, [atom()]) :: Content.t()
  def content(markdown, features),
    do: Content.from_markdown(to_string(markdown), features: features)

  @doc """
  Returns the Markdown of what the editor posts (its document as JSON), or
  of Markdown as it is. Returns `""` for an empty document.
  """
  @spec to_markdown(term()) :: String.t()
  def to_markdown(value) when is_binary(value) or is_map(value) do
    case Content.cast(value) do
      {:ok, %Content{doc: doc}} -> doc_markdown(doc)
      :error when is_binary(value) -> value
      :error -> ""
    end
  end

  def to_markdown(_value), do: ""

  @doc """
  Returns the value of an editor for a form field that holds Markdown, or
  the document that the editor posted (after a `phx-change`).
  """
  @spec editor_value(term(), [atom()]) :: Content.t() | String.t()
  def editor_value(value, features) do
    case Content.cast(value) do
      {:ok, content} -> content
      :error -> content(if(is_binary(value), do: value, else: ""), features)
    end
  end

  @doc """
  Returns the plain text of Markdown on one line, for a list or a search
  result, or `nil` when it has none.
  """
  @spec plain_text(String.t() | nil) :: String.t() | nil
  def plain_text(nil), do: nil

  def plain_text(markdown) do
    markdown
    |> to_string()
    |> Content.from_markdown()
    |> Map.fetch!(:text)
    |> String.split()
    |> Enum.join(" ")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp doc_markdown(doc) do
    case Document.parse(doc) do
      {:ok, document} ->
        if Document.empty?(document),
          do: "",
          else: document |> Renderer.to_markdown() |> String.trim()

      {:error, _messages} ->
        ""
    end
  end

  defp used(%Content{doc: doc}) do
    case Document.parse(doc) do
      {:ok, document} -> Features.used(document)
      {:error, _messages} -> []
    end
  end
end
