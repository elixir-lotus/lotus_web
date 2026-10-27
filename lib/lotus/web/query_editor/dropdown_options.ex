defmodule Lotus.Web.QueryEditor.DropdownOptions do
  @moduledoc """
  The options of a dropdown variable from the rows of a query: the variable's
  own SQL, the SQL the column picker writes, or a saved query.

  The first column is the value and the second the label. A query with one
  column uses it for both, and the columns after the second are left out.
  `preview/2` says so, with what in the rows makes a poor dropdown: values
  that are blank, and values that come more than once.
  """

  use Gettext, backend: Lotus.Web.Gettext

  alias Lotus.Source.Adapter
  alias Lotus.Web.Formatters.VariableOptionsFormatter, as: OptionsFormatter

  @preview_limit 100

  @typedoc """
  What a test run of an options query found:

    * `:options` - the options, at most the preview limit
    * `:columns` - the columns of the rows
    * `:value_column`, `:label_column` - the columns the value and the label
      come from
    * `:ignored_columns` - the columns after the second
    * `:count` - how many options there are, up to the preview limit
    * `:more?` - whether the query has more rows than the preview limit
    * `:warnings` - what to look at in the rows, as sentences
  """
  @type preview :: %{
          options: [map()],
          columns: [String.t()],
          value_column: String.t() | nil,
          label_column: String.t() | nil,
          ignored_columns: [String.t()],
          count: non_neg_integer(),
          more?: boolean(),
          warnings: [String.t()]
        }

  @doc "The most options a test run shows. The run asks for one row more."
  def preview_limit, do: @preview_limit

  @doc """
  The preview of the rows of an options query, `limit` of them shown.
  """
  @spec preview(map(), pos_integer()) :: preview()
  def preview(%{columns: columns, rows: rows}, limit \\ @preview_limit) do
    {shown, rest} = Enum.split(rows, limit)
    value_column = Enum.at(columns, 0)
    label_column = Enum.at(columns, 1, value_column)
    ignored = Enum.drop(columns, 2)

    options =
      if columns == [],
        do: [],
        else: OptionsFormatter.from_lotus_result(%{columns: columns, rows: shown})

    %{
      options: options,
      columns: columns,
      value_column: value_column,
      label_column: label_column,
      ignored_columns: ignored,
      count: length(shown),
      more?: rest != [],
      warnings: warnings(shown, ignored)
    }
  end

  defp warnings(rows, ignored) do
    values = Enum.map(rows, &List.first/1)
    blank = Enum.count(values, &blank?/1)
    repeated = length(values) - (values |> Enum.uniq() |> length())

    [
      blank > 0 &&
        ngettext(
          "1 option has no value (NULL or empty). Filter it out with WHERE … IS NOT NULL.",
          "%{count} options have no value (NULL or empty). Filter them out with WHERE … IS NOT NULL.",
          blank
        ),
      repeated > 0 &&
        ngettext(
          "1 value comes more than once. Add DISTINCT to list each value once.",
          "%{count} values come more than once. Add DISTINCT to list each value once.",
          repeated
        ),
      ignored != [] &&
        ngettext(
          "Only the first two columns are used; %{columns} is left out.",
          "Only the first two columns are used; %{columns} are left out.",
          length(ignored),
          columns: Enum.join(ignored, ", ")
        )
    ]
    |> Enum.filter(& &1)
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  @doc """
  The SQL that lists each value of `value_column` of `table` once, labelled
  by `label_column` when there is one and sorted by the label. `table` is a
  key of the editor's schema, qualified by its schema ("reporting.orders").
  The identifiers are quoted as the source quotes them.
  """
  @spec column_sql(String.t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def column_sql(source, table, value_column, label_column) do
    adapter = Lotus.Source.get_source!(source)
    quote = &Adapter.quote_identifier(adapter, &1)

    table_sql = table |> String.split(".") |> Enum.map_join(".", quote)
    value = quote.(value_column)

    columns =
      if label_column in [nil, "", value_column],
        do: "#{value} AS value",
        else: "#{value} AS value, #{quote.(label_column)} AS label"

    order = if label_column in [nil, "", value_column], do: "value", else: "label"

    "SELECT DISTINCT #{columns} FROM #{table_sql} WHERE #{value} IS NOT NULL ORDER BY #{order}"
  end
end
