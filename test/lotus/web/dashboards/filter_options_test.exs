defmodule Lotus.Web.Dashboards.FilterOptionsTest do
  use Lotus.Web.Case

  alias Lotus.Web.Dashboards.FilterOptions

  setup do
    create_test_users()
    create_test_posts()

    titles =
      query_fixture(%{
        statement: """
        SELECT p.title FROM test_posts p
        JOIN test_users u ON u.id = p.user_id
        WHERE u.name = {{user_name}}
        ORDER BY p.title
        """
      })

    contents =
      query_fixture(%{
        statement: "SELECT content, title FROM test_posts WHERE title = {{post_title}}"
      })

    user_name =
      filter(%{
        id: "new_1",
        name: "user_name",
        config: %{"options" => [%{"value" => "Alice", "label" => "Alice"}, "Bob"]}
      })

    post_title =
      filter(%{
        id: "new_2",
        name: "post_title",
        source_query_id: titles.id,
        depends_on_filter_id: "new_1"
      })

    post_content =
      filter(%{
        id: "new_3",
        name: "post_content",
        source_query_id: contents.id,
        depends_on_filter_id: "new_2"
      })

    {:ok, filters: [post_content, post_title, user_name]}
  end

  test "lists the static options of a select filter with no source query", %{filters: filters} do
    {options, _values} = FilterOptions.resolve(filters, %{})

    assert options["user_name"] ==
             {:ok, [%{value: "Alice", label: "Alice"}, %{value: "Bob", label: "Bob"}]}
  end

  test "waits and clears the value while the parent has no value", %{filters: filters} do
    {options, values} = FilterOptions.resolve(filters, %{"user_name" => "", "post_title" => "X"})

    assert options["post_title"] == :waiting
    assert options["post_content"] == :waiting
    assert values["post_title"] == ""
  end

  test "lists the options of a dependent filter for the parent value", %{filters: filters} do
    {options, _values} = FilterOptions.resolve(filters, %{"user_name" => "Alice"})

    assert options["post_title"] ==
             {:ok,
              [
                %{value: "Draft Post", label: "Draft Post"},
                %{value: "First Post", label: "First Post"}
              ]}
  end

  test "keeps a child value that is in the new options", %{filters: filters} do
    values = %{"user_name" => "Alice", "post_title" => "First Post"}
    {options, values} = FilterOptions.resolve(filters, values)

    assert values["post_title"] == "First Post"
    assert options["post_content"] == {:ok, [%{value: "Hello World", label: "First Post"}]}
  end

  test "clears a child value not in the new options, down the chain", %{filters: filters} do
    values = %{
      "user_name" => "Bob",
      "post_title" => "First Post",
      "post_content" => "Hello World"
    }

    {options, values} = FilterOptions.resolve(filters, values)

    assert values["post_title"] == ""
    assert values["post_content"] == ""
    assert options["post_title"] == {:ok, [%{value: "Another Post", label: "Another Post"}]}
    assert options["post_content"] == :waiting
  end

  test "gives the error of a failing source query and keeps the value", %{filters: filters} do
    broken = query_fixture(%{statement: "SELECT missing_column FROM test_users"})
    filters = Enum.map(filters, &broken_source(&1, broken.id))

    {options, values} =
      FilterOptions.resolve(filters, %{"user_name" => "Alice", "post_title" => "First Post"})

    assert {:error, _reason} = options["post_title"]
    assert values["post_title"] == "First Post"
  end

  test "gives the reason when the source query may not run", %{filters: filters} do
    authorize = fn _query_id -> {:deny, "No query"} end

    {options, _values} =
      FilterOptions.resolve(filters, %{"user_name" => "Alice"}, authorize: authorize)

    assert options["post_title"] == {:error, "No query"}
    assert {:ok, _static} = options["user_name"]
  end

  test "lists no options for a filter without the select widget" do
    text = filter(%{id: 1, name: "search", filter_type: :text, widget: :input})

    assert {%{}, %{"search" => "a"}} == FilterOptions.resolve([text], %{"search" => "a"})
  end

  defp broken_source(%{name: "post_title"} = filter, query_id),
    do: %{filter | source_query_id: query_id}

  defp broken_source(filter, _query_id), do: filter

  defp filter(attrs) do
    Map.merge(
      %{
        filter_type: :select,
        widget: :select,
        label: attrs.name,
        default_value: nil,
        config: %{},
        position: 0,
        source_query_id: nil,
        depends_on_filter_id: nil
      },
      attrs
    )
  end
end
