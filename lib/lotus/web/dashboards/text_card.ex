defmodule Lotus.Web.Dashboards.TextCard do
  @moduledoc """
  A dashboard's text card: Markdown, written in place with Kotoba in edit
  mode, with the dashboard's filter values in it (`{{region}}`).

  A text card with no title whose text is one heading is a heading: it has
  no frame, and names the cards under it. A heading card from before is
  written as one (`as_text/1`).
  """

  use Lotus.Web, :html

  alias Lotus.Web.Dashboards.DateTokens
  alias Lotus.Web.RichText

  @variable ~r/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/

  @doc """
  The Markdown with each `{{name}}` of a filter in `values` as the filter's
  value, written as a reader reads it (a date token's words, a range's two
  dates), and a dash for a filter with no value. A name that is no filter
  stays as it is.

      iex> Lotus.Web.Dashboards.TextCard.fill("Revenue in {{region}}", %{"region" => "North"})
      "Revenue in North"

      iex> Lotus.Web.Dashboards.TextCard.fill("Since {{period}}", %{"period" => "2026-01-01,2026-03-31"})
      "Since 2026-01-01 – 2026-03-31"
  """
  @spec fill(String.t(), %{optional(String.t()) => term()}) :: String.t()
  def fill(markdown, values) when is_binary(markdown) do
    Regex.replace(@variable, markdown, fn whole, name ->
      case Map.fetch(values, name) do
        {:ok, value} -> value |> display() |> escape()
        :error -> whole
      end
    end)
  end

  defp display(value) when value in [nil, ""], do: "—"

  defp display(value) when is_binary(value) do
    cond do
      DateTokens.token?(value) -> DateTokens.label(value)
      String.contains?(value, ",") -> value |> String.split(",", parts: 2) |> Enum.join(" – ")
      true -> value
    end
  end

  defp display(values) when is_list(values), do: Enum.map_join(values, ", ", &display/1)
  defp display(value), do: to_string(value)

  # A value is text, never Markdown: its marks are written as they are.
  defp escape(text), do: String.replace(text, ~r/([\\`*_\[\]<>#|~])/, "\\\\\\1")

  @doc """
  Whether a text card is a heading: no title, and one heading line.

      iex> Lotus.Web.Dashboards.TextCard.heading?(%{title: nil, content: %{"text" => "## Sales"}})
      true

      iex> Lotus.Web.Dashboards.TextCard.heading?(%{title: "About", content: %{"text" => "## Sales"}})
      false
  """
  @spec heading?(map()) :: boolean()
  def heading?(%{card_type: :heading}), do: true

  def heading?(%{title: title} = card) when title in [nil, ""],
    do: text(card) |> String.trim() |> String.match?(~r/\A[#]{1,3} [^\n]+\z/)

  def heading?(_card), do: false

  @doc """
  A heading card as a text card with no title, its text a heading: what
  edit mode makes of the heading cards from before, so that one card writes
  both.
  """
  @spec as_text(map()) :: map()
  def as_text(%{card_type: :heading} = card) do
    # A heading's title was never shown: the text card has none, so that it
    # stays a heading.
    %{card | card_type: :text, title: nil, content: %{"text" => "## " <> String.trim(text(card))}}
  end

  def as_text(card), do: card

  @doc "The Markdown of a card's content."
  @spec text(map()) :: String.t()
  def text(%{content: content}), do: content_text(content)
  def text(_card), do: ""

  defp content_text(%{"text" => text}) when is_binary(text), do: text
  defp content_text(%{text: text}) when is_binary(text), do: text
  defp content_text(text) when is_binary(text), do: text
  defp content_text(_content), do: ""

  @doc """
  The text of a card in a Kotoba editor, in place, in edit mode. It pushes
  each change (`kotoba:change`) to the dashboard editor, which keeps the
  card's text as Markdown.
  """
  attr(:card, :map, required: true)
  attr(:target, :any, required: true)

  def editor(assigns) do
    text = text(assigns.card)
    features = RichText.features(:text_card, text)

    assigns =
      assign(assigns,
        id: "card-text-#{assigns.card.id}",
        features: features,
        # A form of its own: each card's editor has its field's own id.
        field:
          Phoenix.Component.to_form(%{"text" => RichText.content(text, features)},
            as: "card_#{assigns.card.id}"
          )[:text]
      )

    ~H"""
    <%!-- Its clicks write, and do not pick the card (its gear opens its settings). --%>
    <div class="lotus-card-text h-full" phx-click={%JS{}}>
      <Kotoba.Components.kotoba
        field={@field}
        id={@id}
        label_id={"card-#{@card.id}-title"}
        placeholder={gettext("Write here. # for a heading; {{filter}} for a filter's value.")}
        features={@features}
        change
        debounce={300}
        phx-target={@target}
      />
    </div>
    """
  end
end
