defmodule Lotus.Web.Commands do
  @moduledoc """
  The actions of the command palette (⌘K), with `Jumon`.

  The palette offers the pages of the dashboard, what the user may create,
  the appearance and the theme, and it searches the saved queries and the
  dashboards. `page_actions/2` adds the actions of the page in view: the
  query editor's toolbar, or the dashboard's.

  Actions that drive the page click its own buttons in the browser (the
  `lotus:click` event, handled in `app.js`), so the palette does what the
  button does, with its permissions and its state.
  """

  use Jumon.Commands
  use Gettext, backend: Lotus.Web.Gettext

  import Lotus.Web.Helpers, only: [lotus_path: 1, lotus_path: 2]

  alias Lotus.Web.Authorization
  alias Phoenix.LiveView.JS

  @search_limit 20

  @impl Jumon.Commands
  def actions(socket) do
    assigns = socket.assigns

    [
      action(:queries, gettext("Queries"),
        section: gettext("Go to"),
        icon: "terminal",
        navigate: lotus_path("")
      ),
      action(:dashboards, gettext("Dashboards"),
        section: gettext("Go to"),
        icon: "blocks",
        navigate: lotus_path("", %{tab: "dashboards"})
      )
    ] ++
      create_actions(assigns) ++
      [appearance_action()] ++
      theme_actions(assigns)
  end

  @impl Jumon.Commands
  def sources(socket) do
    assigns = socket.assigns

    [
      queries: [label: gettext("Queries"), search: &search_queries/1],
      dashboards: [label: gettext("Dashboards"), search: &search_dashboards(assigns, &1)]
    ]
  end

  @doc """
  The actions of the page in view, for `Jumon.Live.put_actions/2`.
  """
  @spec page_actions(atom(), map()) :: [Jumon.Action.t()]
  def page_actions(:query_editor, _assigns) do
    section = gettext("Query")

    [
      click(:run_query, gettext("Run query"), "#toolbar-run-query-btn",
        section: section,
        icon: "play",
        keywords: ~w(execute)
      ),
      click(:schema_explorer, gettext("Toggle schema explorer"), "#schema-explorer-btn",
        section: section,
        icon: "database",
        keywords: ~w(tables columns)
      ),
      click(:variable_settings, gettext("Toggle variable settings"), "#variable-settings-btn",
        section: section,
        icon: "variable"
      ),
      click(:visualization, gettext("Toggle visualization settings"), "#visualization-btn",
        section: section,
        icon: "chart_bar",
        keywords: ~w(chart graph)
      ),
      click(:copy_query, gettext("Copy query to clipboard"), "#copy-query-btn",
        section: section,
        icon: "clipboard_copy"
      )
    ] ++ ai_actions(section)
  end

  def page_actions(:dashboard_editor, assigns) do
    if Authorization.allowed?(assigns, :manage_dashboard) do
      [
        click(:add_card, gettext("Add card"), "#add-card-btn",
          section: gettext("Dashboard"),
          icon: "plus"
        )
      ]
    else
      []
    end
  end

  def page_actions(_page, _assigns), do: []

  ## Actions

  defp create_actions(assigns) do
    section = gettext("Create")

    [
      Authorization.allowed?(assigns, :create_query) &&
        action(:new_query, gettext("New query"),
          section: section,
          icon: "plus",
          navigate: lotus_path(["queries", "new"])
        ),
      Authorization.allowed?(assigns, :manage_dashboard) &&
        action(:new_dashboard, gettext("New dashboard"),
          section: section,
          icon: "plus",
          navigate: lotus_path(["dashboards", "new"])
        )
    ]
    |> Enum.filter(& &1)
  end

  # The assistant's button shows only where the user may use it on the
  # query's source; the action clicks it, so it does nothing elsewhere.
  defp ai_actions(section) do
    if Lotus.AI.enabled?() do
      [
        click(:ai_assistant, gettext("Ask AI…"), "#ai-assistant-btn",
          section: section,
          icon: "sparkles",
          keywords: ~w(assistant generate)
        )
      ]
    else
      []
    end
  end

  # Light, dark or system: the options of the appearance menu.
  defp appearance_action do
    action(:appearance, gettext("Appearance"),
      section: gettext("Settings"),
      icon: "sun",
      keywords: ~w(light dark mode),
      children: [
        click(:appearance_light, gettext("Light"), ~s([data-theme-option="light"]), icon: "sun"),
        click(:appearance_dark, gettext("Dark"), ~s([data-theme-option="dark"]), icon: "moon"),
        click(:appearance_system, gettext("System"), ~s([data-theme-option="system"]),
          icon: "monitor"
        )
      ]
    )
  end

  # The themes on offer (the :themes option of lotus_dashboard/2), when there
  # is a choice.
  defp theme_actions(assigns) do
    case Map.get(assigns, :themes, []) do
      [_, _ | _] = themes ->
        [
          action(:theme, gettext("Theme"),
            section: gettext("Settings"),
            icon: "layers",
            children:
              for theme <- themes do
                click("theme-#{theme}", theme_label(theme), ~s([data-palette-option="#{theme}"]))
              end
          )
        ]

      _one ->
        []
    end
  end

  defp theme_label(:lotus), do: "Lotus"
  defp theme_label(:sumi), do: "Sumi"

  # An action that clicks a button of the page, if it is there.
  defp click(id, name, selector, opts \\ []) do
    action(id, name, Keyword.put(opts, :js, JS.dispatch("lotus:click", detail: %{to: selector})))
  end

  ## Sources

  # Ranked with the palette's own rules (Jumon.Match): a typo or an accent
  # still finds a query or a dashboard.
  defp search_queries(query) do
    Lotus.list_queries()
    |> Enum.map(fn stored ->
      action("query-#{stored.id}", stored.name,
        subtitle: stored.description,
        icon: "terminal",
        navigate: lotus_path(["queries", stored.id])
      )
    end)
    |> best(query)
  end

  defp search_dashboards(assigns, query) do
    Lotus.list_dashboards()
    |> Enum.filter(&Authorization.allowed?(assigns, :view_dashboard, &1))
    |> Enum.map(fn dashboard ->
      action("dashboard-#{dashboard.id}", dashboard.name,
        subtitle: dashboard.description,
        icon: "blocks",
        navigate: lotus_path(["dashboards", dashboard.id])
      )
    end)
    |> best(query)
  end

  defp best(actions, query) do
    actions
    |> Jumon.Match.rank(query)
    |> Enum.take(@search_limit)
    |> Enum.map(fn {action, _result} -> action end)
  end

  @doc """
  The icon names that the actions and the results use, for the palette's
  `:icon` slot.
  """
  @spec icons() :: [String.t()]
  def icons,
    do: ~w(terminal blocks plus play database variable chart_bar clipboard_copy sparkles
           sun moon monitor layers)
end
