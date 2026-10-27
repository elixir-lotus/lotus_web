defmodule Lotus.Web.SchemaBuilderSchemalessTest do
  # A source without schemas (Elasticsearch's indices, say) lists its tables
  # under a stand-in schema; the editor describes them without one.
  use Lotus.Web.Case, async: false

  alias Lotus.Web.SchemaBuilder
  alias Lotus.Web.SourcesMap

  defmodule FlatAdapter do
    @behaviour Lotus.Source.Adapter
    @behaviour Lotus.Source.Adapter.Introspection

    alias Lotus.Source.Adapter

    @impl Adapter
    def can_handle?(%{adapter: __MODULE__}), do: true
    def can_handle?(_), do: false

    @impl Adapter
    def wrap(name, _entry),
      do:
        Adapter.with_capabilities(%Adapter{
          name: name,
          module: __MODULE__,
          state: %{},
          source_type: :flat
        })

    @impl Adapter
    def execute_query(_state, _body, _params, _opts),
      do: {:ok, %{columns: [], rows: [], num_rows: 0}}

    @impl Adapter
    def transaction(state, fun, _opts), do: {:ok, fun.(state)}
    @impl Adapter
    def list_tables(_state, _schemas, _opts), do: {:ok, [{nil, "orders"}]}
    @impl Adapter
    def describe_table(_state, nil, "orders"),
      do:
        {:ok,
         [%{name: "status", type: "keyword", nullable: true, default: nil, primary_key: false}]}

    def describe_table(_state, schema, table), do: {:error, "no #{inspect(schema)}.#{table}"}
    @impl Adapter
    def builtin_denies(_state), do: []
    @impl Adapter
    def health_check(_state), do: :ok
    @impl Adapter
    def disconnect(_state), do: :ok
    @impl Adapter
    def format_error(_state, error), do: inspect(error)
    @impl Adapter
    def source_type(_state), do: :flat

    @impl Lotus.Source.Adapter.Introspection
    def list_schemas(_state), do: {:ok, []}
    @impl Lotus.Source.Adapter.Introspection
    def resolve_table_namespace(_state, _table, _schemas), do: {:ok, nil}
    @impl Lotus.Source.Adapter.Introspection
    def default_schemas(_state), do: []
    @impl Lotus.Source.Adapter.Introspection
    def builtin_schema_denies(_state), do: []
    @impl Lotus.Source.Adapter.Introspection
    def hierarchy_label(_state), do: "Indices"
    @impl Lotus.Source.Adapter.Introspection
    def parse_qualified_name(_state, name), do: {:ok, [name]}
    @impl Lotus.Source.Adapter.Introspection
    def validate_identifier(_state, _kind, _value), do: :ok
  end

  setup do
    sources = Application.get_env(:lotus, :data_sources)
    adapters = Application.get_env(:lotus, :source_adapters)

    Application.put_env(:lotus, :data_sources, Map.put(sources, "flat", %{adapter: FlatAdapter}))
    Application.put_env(:lotus, :source_adapters, [FlatAdapter | List.wrap(adapters)])
    Lotus.Config.reload!()

    on_exit(fn ->
      restore(:data_sources, sources)
      restore(:source_adapters, adapters)
      Lotus.Config.reload!()
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:lotus, key)
  defp restore(key, value), do: Application.put_env(:lotus, key, value)

  test "describes a table of a source without schemas, with its types" do
    sources_map = SourcesMap.build()

    assert {:ok, %{"orders" => nil}} = SchemaBuilder.build(sources_map, "flat")

    assert {:ok, %{"orders" => [%{name: "status", type: "keyword"}]}} =
             SchemaBuilder.describe(sources_map, "flat", nil, ["orders"])

    assert {:ok, %{"orders" => ["status"]}} =
             SchemaBuilder.columns(sources_map, "flat", nil, ["orders"])
  end
end
