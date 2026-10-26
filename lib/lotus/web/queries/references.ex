defmodule Lotus.Web.Queries.References do
  @moduledoc false

  # Following a foreign key from the results to the row it references.
  #
  # Lotus knows a result's columns only by name. A result column is a column
  # of a table only when the statement says so plainly: `SELECT <columns> FROM
  # <one table>`, each column a bare name (or `*`), with no join, union,
  # grouping or aliases, then a WHERE, ORDER BY, LIMIT or OFFSET. Of such a
  # result, the columns that are a foreign key of the table (`describe_table`,
  # `:references`) open the row they reference. Of any other statement, none
  # do: a guess would open the wrong rows.
  #
  # The row opens in a new query, `SELECT * FROM <table> WHERE <column> =
  # {{column}}`, with the value as the variable's: the value is bound, never
  # written into the statement, and the identifiers are the ones the source
  # described, quoted by its adapter.

  alias Lotus.Source.Adapter
  alias Lotus.Storage.Query
  alias Lotus.Storage.QueryVariable

  @ident ~S/(?:[A-Za-z_][A-Za-z0-9_$]*|"(?:[^"]|"")+"|`(?:[^`]|``)+`)/

  # Compiled when used: a compiled regex cannot be a module attribute on
  # every OTP release Lotus supports.
  defp select_regex do
    Regex.compile!(
      "\\A\\s*select\\s+(?:all\\s+|distinct\\s+)?(?<columns>.+?)\\s+from\\s+" <>
        "(?<relation>#{@ident}(?:\\s*\\.\\s*#{@ident})?)" <>
        "(?:\\s+(?:as\\s+)?(?<alias>#{@ident}))?" <>
        "(?<rest>\\s+(?:where|order\\s+by|limit|offset|fetch)\\b.*)?" <>
        "\\s*;?\\s*\\z",
      "is"
    )
  end

  defp column_regex,
    do: Regex.compile!("\\A(?:(?<qualifier>#{@ident})\\s*\\.\\s*)?(?<name>\\*|#{@ident})\\z", "s")

  # Words that change which rows or columns a statement gives, comments, and
  # a second statement.
  defp unsafe?(statement) do
    Regex.match?(
      ~r/\b(?:union|intersect|except|join|group\s+by|having|window)\b|--|\/\*|;.*\S/is,
      statement
    )
  end

  @typedoc "A foreign key of a result column: the table and column it references."
  @type foreign_key :: %{schema: String.t() | nil, table: String.t(), column: String.t()}

  @doc """
  The table a statement reads, as `{schema, table}`, when its result columns
  are that table's columns as they are; `:error` otherwise.
  """
  @spec single_table(String.t()) :: {:ok, {String.t() | nil, String.t()}} | :error
  def single_table(statement) when is_binary(statement) do
    with %{"columns" => columns, "relation" => relation} = parts <-
           Regex.named_captures(select_regex(), statement),
         false <- unsafe?(statement),
         false <- Regex.match?(~r/\A(?:where|order|limit|offset|fetch|join)\z/i, parts["alias"]),
         {schema, table} <- relation(relation),
         true <- plain_columns?(columns, [table, unquote_ident(parts["alias"])]) do
      {:ok, {schema, table}}
    else
      _ -> :error
    end
  end

  def single_table(_statement), do: :error

  defp relation(relation) do
    case Regex.scan(Regex.compile!(@ident), relation) do
      [[table]] -> {nil, unquote_ident(table)}
      [[schema], [table]] -> {unquote_ident(schema), unquote_ident(table)}
      _ -> :error
    end
  end

  defp plain_columns?(columns, names) do
    columns
    |> String.split(",")
    |> Enum.all?(fn column ->
      case Regex.named_captures(column_regex(), String.trim(column)) do
        %{"qualifier" => ""} -> true
        %{"qualifier" => qualifier} -> unquote_ident(qualifier) in names
        nil -> false
      end
    end)
  end

  defp unquote_ident("\"" <> _ = ident),
    do: ident |> String.slice(1..-2//1) |> String.replace(~s(""), ~s("))

  defp unquote_ident("`" <> _ = ident),
    do: ident |> String.slice(1..-2//1) |> String.replace("``", "`")

  defp unquote_ident(ident), do: ident

  @doc """
  The foreign keys of a result's columns, `%{column => reference}`, when the
  statement reads one table plainly (`single_table/1`) of a SQL source;
  `%{}` otherwise, or when the source cannot describe the table.

  `opts` are the actor's (`:context`, `:scope`) and the query's
  `:search_path`.
  """
  @spec for_result(String.t(), String.t(), [String.t()], keyword()) :: %{
          String.t() => foreign_key()
        }
  def for_result(source, statement, columns, opts \\ []) do
    with true <- sql_source?(source),
         true <- columns == Enum.uniq(columns),
         {:ok, {schema, table}} <- single_table(statement),
         {:ok, described} <- describe(source, schema, table, opts) do
      for %{name: name, references: %{table: _} = ref} <- described,
          name in columns,
          into: %{},
          do: {name, Map.take(ref, [:schema, :table, :column])}
    else
      _ -> %{}
    end
  rescue
    _error -> %{}
  end

  defp sql_source?(source) do
    match?("sql:" <> _, Lotus.Source.query_language(source))
  rescue
    _error -> false
  end

  # Postgres folds an unquoted name to lower case.
  defp describe(source, schema, table, opts) do
    opts =
      if schema,
        do: opts |> Keyword.delete(:search_path) |> Keyword.put(:schema, schema),
        else: opts

    case Lotus.describe_table(source, table, opts) do
      {:ok, columns} ->
        {:ok, columns}

      {:error, _} = error ->
        lower = String.downcase(table)
        if lower != table, do: Lotus.describe_table(source, lower, opts), else: error
    end
  end

  @doc """
  The query that opens the row a foreign key references: `SELECT * FROM
  <table> WHERE <column> = {{variable}}`, and the variable's values, when the
  person may see the table and its column; `:error` otherwise.

  `opts` are the actor's (`:context`, `:scope`).
  """
  @spec lookup(String.t(), String.t() | nil, String.t(), String.t(), String.t(), keyword()) ::
          {:ok, %Query{}, %{String.t() => String.t()}} | :error
  def lookup(source, schema, table, column, value, opts \\ []) do
    describe_opts = if schema in [nil, ""], do: opts, else: Keyword.put(opts, :schema, schema)

    with true <- sql_source?(source),
         {:ok, columns} <- Lotus.describe_table(source, table, describe_opts),
         %{} = described <- Enum.find(columns, &(&1.name == column)) do
      adapter = Lotus.Source.resolve!(source, nil)
      quote = &Adapter.quote_identifier(adapter, &1)
      name = variable_name(column)

      relation =
        if schema in [nil, ""],
          do: quote.(table),
          else: quote.(schema) <> "." <> quote.(table)

      query = %Query{
        name: "",
        description: "",
        statement: "SELECT * FROM #{relation} WHERE #{quote.(column)} = {{#{name}}}",
        data_source: source,
        variables: [
          %QueryVariable{
            name: name,
            type: variable_type(described),
            widget: :input,
            label: column
          }
        ]
      }

      {:ok, query, %{name => value}}
    else
      _ -> :error
    end
  rescue
    _error -> :error
  end

  defp variable_name(column) do
    if Regex.match?(~r/\A[A-Za-z_]\w*\z/, column), do: column, else: "value"
  end

  # A number is cast as one; text, UUIDs and the rest as the source reads them.
  defp variable_type(%{type: type}) when is_binary(type) do
    if Regex.match?(~r/int|numeric|decimal|real|double|float|serial/i, type),
      do: :number,
      else: :text
  end

  defp variable_type(_column), do: :text

  @doc "A cell's value as text, for the variable of the row it opens."
  @spec value_text(term()) :: String.t() | nil
  def value_text(nil), do: nil
  def value_text(value) when is_binary(value), do: value
  def value_text(%Decimal{} = value), do: Decimal.to_string(value)
  def value_text(%Date{} = value), do: Date.to_iso8601(value)
  def value_text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def value_text(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def value_text(value) when is_number(value) or is_boolean(value), do: to_string(value)
  def value_text(value), do: Lotus.Value.to_display_string(value)
end
