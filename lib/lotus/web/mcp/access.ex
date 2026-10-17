if Code.ensure_loaded?(Sake.Server) do
  defmodule Lotus.Web.MCP.Access do
    @moduledoc """
    Asks the `Lotus.Web.Resolver` about every MCP call, with the action the
    dashboard would ask about for the same thing.

    | Tool | Action | Resource |
    |---|---|---|
    | `list_data_sources` | `:discover` or `:query` | each source listed |
    | `list_schemas`, `list_tables`, `describe_table` | `:discover` or `:query` | the data source |
    | `get_column_values`, `run_sql` | `:query` | the data source |
    | `list_queries` | `:query` | each query's data source |
    | `get_query`, `run_query`, `show_chart` | `:query` | the query's data source |
    | `save_query` | `:create_query`, and `:query` | `nil`, and the data source |
    | `update_query`, `save_chart` | `:update_query` | the query |
    | `list_dashboards` | `:view_dashboard` | each dashboard listed |
    | `get_dashboard`, `run_dashboard` | `:view_dashboard` | the dashboard |
    | `create_dashboard` | `:manage_dashboard` | `nil` |
    | `add_dashboard_card` | `:manage_dashboard`, and `:query` for a query card | the dashboard, and the query's data source |

    A resource needs `:query` (a saved query, on its data source; the chart
    app) or `:view_dashboard` (a dashboard).

    The tool list shows what the access level allows (and, for actions that
    take no resource, what `authorize/3` allows); the call asks
    `authorize/3` with the resource. A list tool's result leaves out what
    the person may not see. A tool this table does not name is not listed,
    so a tool a later Lotus adds stays hidden until Lotus Web maps it.
    """

    alias Lotus.Web.{Authorization, Resolver}

    @actions %{
      "list_data_sources" => :discover,
      "list_schemas" => :discover,
      "list_tables" => :discover,
      "describe_table" => :discover,
      "get_column_values" => :query,
      "run_sql" => :query,
      "list_queries" => :query,
      "get_query" => :query,
      "run_query" => :query,
      "show_chart" => :query,
      "save_query" => :create_query,
      "update_query" => :update_query,
      "save_chart" => :update_query,
      "list_dashboards" => :view_dashboard,
      "get_dashboard" => :view_dashboard,
      "run_dashboard" => :view_dashboard,
      "create_dashboard" => :manage_dashboard,
      "add_dashboard_card" => :manage_dashboard,
      "lotus://queries/{id}" => :query,
      "lotus://dashboards/{id}" => :view_dashboard,
      "ui://lotus/chart" => :query
    }

    @resourceless [:create_query]

    @doc false
    def init(opts), do: opts

    @doc false
    def call(%{result: result} = payload, _opts) when is_map_key(payload, :tool),
      do: {:cont, %{payload | result: filter_result(payload.tool.name, result, who(payload))}}

    def call(%{items: items} = payload, _opts) do
      who = who(payload)
      {:cont, %{payload | items: Enum.filter(items, &listed?(&1, who))}}
    end

    def call(%{tool: tool, arguments: args} = payload, _opts) do
      case check_call(tool.name, args, who(payload)) do
        :ok -> {:cont, payload}
        {:deny, reason} -> {:halt, {:tool_error, reason}}
      end
    end

    def call(%{resource: resource, params: params} = payload, _opts) do
      case check_read(resource.uri, params, who(payload)) do
        :ok -> {:cont, payload}
        {:deny, reason} -> {:halt, {:error, reason}}
      end
    end

    def call(payload, _opts), do: {:cont, payload}

    # ---- who

    # No resolver, or one without resolve_access/1, is no access: the
    # dashboard's default (:all) is for a route behind the host's pipeline.
    defp who(%{ctx: ctx}) do
      resolver = Lotus.Web.MCP.resolver()
      user = ctx.scope

      access =
        if resolver && Resolver.implements?(resolver, :resolve_access, 1),
          do: resolver.resolve_access(user),
          else: :forbidden

      {resolver, user, access}
    end

    defp decide({resolver, user, access}, action, resource),
      do: Authorization.decide(resolver, user, access, action, resource)

    # ---- the list

    defp listed?(_spec, {_resolver, _user, access}) when access not in [:all, :read_only],
      do: false

    defp listed?(spec, {_resolver, _user, access} = who) do
      case Map.fetch(@actions, name_or_uri(spec)) do
        {:ok, action} when action in @resourceless -> decide(who, action, nil) == :allow
        {:ok, action} -> Authorization.default_decision(access, action) == :allow
        :error -> false
      end
    end

    defp name_or_uri(%Sake.Resource.Spec{uri: uri}), do: uri
    defp name_or_uri(spec), do: spec.name

    # ---- a call

    defp check_call(name, args, who) when name in ~w(list_schemas list_tables describe_table) do
      if discoverable?(who, args[:data_source]),
        do: :ok,
        else: {:deny, Authorization.reason(:discover)}
    end

    defp check_call(name, args, who) when name in ~w(get_column_values run_sql),
      do: decide(who, :query, args[:data_source]) |> result()

    defp check_call(name, %{id: id}, who) when name in ~w(get_query run_query),
      do: query_source(id, who)

    defp check_call("show_chart", %{query_id: id}, who) when is_integer(id),
      do: query_source(id, who)

    defp check_call("show_chart", args, who),
      do: decide(who, :query, args[:data_source]) |> result()

    defp check_call("save_query", args, who) do
      with :ok <- decide(who, :create_query, nil) |> result(),
           do: decide(who, :query, args[:data_source]) |> result()
    end

    defp check_call("update_query", %{id: id} = args, who) do
      with :ok <- with_query(id, &(decide(who, :update_query, &1) |> result())) do
        if args[:data_source], do: decide(who, :query, args[:data_source]) |> result(), else: :ok
      end
    end

    defp check_call("save_chart", %{query_id: id}, who),
      do: with_query(id, &(decide(who, :update_query, &1) |> result()))

    defp check_call(name, %{id: id}, who) when name in ~w(get_dashboard run_dashboard),
      do: with_dashboard(id, &(decide(who, :view_dashboard, &1) |> result()))

    defp check_call("create_dashboard", _args, who),
      do: decide(who, :manage_dashboard, nil) |> result()

    defp check_call("add_dashboard_card", %{dashboard_id: id} = args, who) do
      with :ok <- with_dashboard(id, &(decide(who, :manage_dashboard, &1) |> result())) do
        if is_integer(args[:query_id]), do: query_source(args[:query_id], who), else: :ok
      end
    end

    # The list tools filter their results instead (filter_result/3).
    defp check_call(name, _args, _who)
         when name in ~w(list_data_sources list_queries list_dashboards),
         do: :ok

    defp check_call(_name, _args, _who), do: {:deny, "This tool is not available"}

    defp discoverable?(who, source),
      do: decide(who, :discover, source) == :allow or decide(who, :query, source) == :allow

    defp query_source(id, who), do: with_query(id, &(decide(who, :query, source(&1)) |> result()))

    # A missing record is the tool's to report.
    defp with_query(id, fun) do
      case Lotus.get_query(id) do
        nil -> :ok
        query -> fun.(query)
      end
    end

    defp with_dashboard(id, fun) do
      case Lotus.get_dashboard(id) do
        nil -> :ok
        dashboard -> fun.(dashboard)
      end
    end

    defp source(%{data_source: nil}), do: elem(Lotus.default_data_source(), 0)
    defp source(%{data_source: source}), do: source

    defp result(:allow), do: :ok
    defp result({:deny, reason}), do: {:deny, reason}

    # ---- a read

    defp check_read("lotus://queries/{id}", %{id: id}, who) do
      case Integer.parse(id) do
        {id, ""} -> query_source(id, who)
        _ -> :ok
      end
    end

    defp check_read("lotus://dashboards/{id}", %{id: id}, who) do
      case Integer.parse(id) do
        {id, ""} -> with_dashboard(id, &(decide(who, :view_dashboard, &1) |> result()))
        _ -> :ok
      end
    end

    defp check_read("ui://lotus/chart", _params, _who), do: :ok
    defp check_read(_uri, _params, _who), do: {:deny, "Not found"}

    # ---- a list tool's result

    defp filter_result("list_data_sources", result, who),
      do: filter_items(result, "data_sources", &discoverable?(who, &1["name"]))

    defp filter_result("list_queries", result, who) do
      default = elem(Lotus.default_data_source(), 0)

      filter_items(
        result,
        "queries",
        &(decide(who, :query, &1["data_source"] || default) == :allow)
      )
    end

    defp filter_result("list_dashboards", result, who) do
      dashboards = Map.new(Lotus.list_dashboards(), &{&1.id, &1})

      filter_items(result, "dashboards", fn item ->
        case dashboards[item["id"]] do
          nil -> false
          dashboard -> decide(who, :view_dashboard, dashboard) == :allow
        end
      end)
    end

    defp filter_result(_name, result, _who), do: result

    # The list in structuredContent, and the JSON text that repeats it.
    defp filter_items(%{"structuredContent" => %{} = structured} = result, key, keep?) do
      case structured do
        %{^key => items} when is_list(items) ->
          structured = Map.put(structured, key, Enum.filter(items, keep?))

          %{
            result
            | "structuredContent" => structured,
              "content" => [%{"type" => "text", "text" => JSON.encode!(structured)}]
          }

        _ ->
          result
      end
    end

    defp filter_items(result, _key, _keep?), do: result
  end
end
