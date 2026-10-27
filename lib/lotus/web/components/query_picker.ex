defmodule Lotus.Web.Components.QueryPicker do
  @moduledoc """
  The picker of a saved query, wherever one is chosen: Erabi's `select`,
  with a box to search the queries by name, data source and description.

  It posts what a `<select>` would (`name` and the query's id), so it goes
  in a form with `phx-change` as one does.

      <.query_picker id="add-card-query" name="query_id" value={@query_id} queries={@queries} />
  """

  use Phoenix.Component
  use Gettext, backend: Lotus.Web.Gettext

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:value, :any, default: nil)
  attr(:queries, :list, required: true, doc: "the queries to choose from")

  attr(:missing, :string,
    default: nil,
    doc: "the label of a chosen id that is not one of `queries`, such as a deleted query"
  )

  attr(:label_id, :string, default: nil, doc: "the id of the element that labels the picker")
  attr(:placeholder, :string, default: nil)
  attr(:rest, :global, include: ~w(form))

  def query_picker(assigns) do
    assigns =
      assigns
      |> assign(:options, options(assigns.queries))
      |> assign(:selected, selected(assigns))
      |> assign_new(:placeholder_text, fn -> assigns.placeholder || gettext("Search queries…") end)

    ~H"""
    <Erabi.Components.select
      id={@id}
      name={@name}
      value={@value}
      options={@options}
      selected={@selected}
      label_id={@label_id}
      label={gettext("Saved query")}
      placeholder={@placeholder_text}
      filter
      {@rest}
    />
    """
  end

  defp options(queries) do
    Enum.map(queries, fn query ->
      %{
        value: query.id,
        label: query.name,
        hint: query.data_source,
        keywords: List.wrap(Map.get(query, :description))
      }
    end)
  end

  # A chosen id that is not one of the queries still shows, by `missing`.
  defp selected(%{value: value, missing: missing, queries: queries})
       when value not in [nil, ""] and is_binary(missing) do
    if Enum.any?(queries, &(to_string(&1.id) == to_string(value))),
      do: [],
      else: [%{value: value, label: missing}]
  end

  defp selected(_assigns), do: []
end
