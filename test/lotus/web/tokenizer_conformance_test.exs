defmodule Lotus.Web.TokenizerConformanceTest do
  # The editor's tokenizer (assets/js/lib/languages/sql/tokenizer.js) reads
  # SQL and JSON as Lotus's (`Lotus.Query.Tokenizer`) does. This test writes
  # what Lotus makes of a corpus of statements, per dialect, to a fixture the
  # JS tests hold the editor's tokenizer to (tokenizer_conformance.test.js).
  #
  # For JSON sources (Elasticsearch) the fixture also says, for a corpus of
  # templates, which variables Lotus finds and whether the request is valid
  # JSON once Lotus has kept or dropped its `[[ ]]` blocks and a value is
  # bound to each variable, as the Elasticsearch adapter binds them: the
  # editor's JSON checks are held to it (json_template_conformance.test.js).
  #
  # The fixture is committed. When Lotus reads SQL differently, this test
  # fails until the fixture is written again, and then the JS test fails
  # until the editor reads it the same way:
  #
  #     UPDATE_TOKENIZER_FIXTURE=1 mix test test/lotus/web/tokenizer_conformance_test.exs
  use ExUnit.Case, async: true

  import Bitwise

  alias Lotus.Query.Tokenizer
  alias Lotus.Query.Tokenizer.Profile

  @fixture Path.expand("../../../assets/test/fixtures/tokenizer_conformance.json", __DIR__)

  # Editor dialect name => Lotus query language.
  @dialects [
    {"postgres", "sql:postgres"},
    {"mysql", "sql:mysql"},
    {"sqlite", "sql:sqlite"},
    {"ansi", "sql"},
    {"json", "json:elasticsearch"}
  ]

  # Search requests, as people write them with variables and blocks.
  @json_corpus [
    ~S|{"query": {"match_all": {}}}|,
    ~S|{"query": {"term": {"status": "{{status}}"}}, "size": {{limit}}}|,
    ~S|{"query": {"wildcard": {"name": "*{{q}}*"}}}|,
    ~S|{"q": "a \"quoted\" {{x}} [[y]] } {", "n": 1}|,
    ~S|{"size": 10 [[, "from": {{offset}}]]}|,
    ~S|{"query": {"bool": {"filter": [{"match_all": {}}] [[, "must": {"term": {"a": "{{a}}"}}]]}}}|,
    ~S|{"query": {"bool": {"filter": [{"match_all": {}} [[, {"term": {"a": "{{a}}"}}]]]}}}|,
    ~S|{"f": [{"a": 1} [[, {"b": {{b}}}]] [[, {"c": "{{c}}"}]]]}|,
    ~S|{"f": ["x" [[, "{{y}}"]], 1 [[, {{z}}]], true [[, null]]]}|,
    ~S|{"f": [ [[ {"x": {{x}}}, ]] {"y": 1}]}|,
    ~S|{"g": [[1, 2], [[3, 4]]], "h": [0, [[5]]]}|,
    "{\"f\": [1\u00a0[[, 2]]]}",
    ~S|{"c": [[1, 2], [3, 4]]}|,
    ~S|{"a": 1 [[, "b": 2 [[, "c": {{c}}]]]]}|,
    ~S|{"a": [[{{x}}]]}|,
    ~S|{"{{field}}": {{value}}}|,
    ~S|{"a": {{ x }}}|,
    ~S|{"a": {{1x}}}|,
    ~S|{"a": 1,}|,
    ~S|{"a": 1 "b": 2}|,
    ~S|{a: 1}|,
    ~S|{"a": 'x'}|,
    ~S|{"a": 01}|,
    ~S|{"a": -1.5e3, "b": true, "c": null, "d": [], "e": {}}|,
    ~S|{"a": tru}|,
    ~S|{"a": "x" // note
}|,
    ~S|[{"a": 1}]|,
    ~S|{"a": "unterminated|,
    ~S|{"a": {"b": 1}|,
    ~S|{"a": 1}}|,
    ~S|{"a": [1, 2,]}|,
    ~S|{"a": "tab	in string"}|,
    ~S|{"a": "\u00e9 \n"}|,
    ~S|{"a": "\x"}|,
    "",
    ~S|{"size": {{n}} [[, "sort": [{"{{field}}": "{{dir}}"}]]]}|,
    ~S|{"aggs": {"by_{{x}}": {"terms": {"field": "{{x}}"}}}}|,
    ~S|{"a": 1 [[, "b": {{b}},]]}|,
    ~S|{[[ "a": {{a}}, ]] "b": 1}|
  ]

  # Statements at the edges of each dialect's rules.
  @corpus @json_corpus ++
            [
              "SELECT 1",
              "SELECT 'it''s; fine' AS s; SELECT 2",
              ~S|SELECT E'it\'s; DROP' AS x; SELECT 1|,
              ~S|SELECT e'a\'b', nameE'c', 1E'd'|,
              "SELECT $$a;b$$, $tag$x$$y$tag$, foo$bar$ FROM t WHERE a = $1",
              "SELECT $1x$ab$1x$",
              "SELECT ARRAY[[1,2],[3,4]] [[WHERE x = {{x}}]]",
              "SELECT ARRAY [[1]], arr[1][2], x[y[1]] FROM t",
              "SELECT * FROM t [[WHERE a = arr[y[1]]]]",
              "SELECT * FROM t WHERE 1=1 [[AND a = {{a}} [[AND b = {{b}}]]]]",
              "SELECT active[[1]] FROM t",
              "SELECT * FROM t [[ WHERE open",
              "SELECT * FROM t ]] closed",
              "SELECT 5--1, 5 -- comment\n, 6",
              "SELECT 1 # hash comment\n, 2",
              "SELECT 1 /*! , secret */ FROM t",
              "SELECT 1 /*+ hint */ FROM t",
              "SELECT /* a /* nested */ b */ 1",
              "SELECT 1 -- x\rDROP TABLE t",
              "SELECT 1 -- x\r\nSELECT 2",
              "SELECT [weird;name], \"q\"\"d\", `b``t` FROM t",
              ~S|SELECT "a\"b", 'c\'d', 'e\\' FROM t|,
              "SELECT {{a}}, {{ b }}, {{c d}}, '{{inside}}' FROM t",
              "SELECT {{{a}}}, {{{{b}}}}, {{1}}{{c}} FROM t",
              "SELECT 'unclosed",
              "SELECT \"unclosed",
              "SELECT /* unclosed",
              "SELECT $q$unclosed",
              "SELECT 'é' AS café, \"日本\" FROM t",
              "SELECT '😀', `😀` -- 😀\n FROM t"
            ]

  @update """
  Write the fixture again, then make the editor's tokenizer agree (npm test):

      UPDATE_TOKENIZER_FIXTURE=1 mix test test/lotus/web/tokenizer_conformance_test.exs
  """

  @random_cases 400
  @alphabet [
    "'",
    "\"",
    "`",
    "$",
    "[",
    "]",
    "[[",
    "]]",
    "{",
    "}",
    "{{",
    "}}",
    "-",
    "--",
    "/",
    "*",
    "/*",
    "*/",
    "#",
    "!",
    "\\",
    ";",
    "(",
    ")",
    ",",
    ".",
    ":",
    "E",
    "e",
    "x",
    "tag",
    "1",
    "0",
    "é",
    "😀",
    " ",
    "\n",
    "\r",
    "\t",
    "SELECT ",
    "FROM ",
    "ARRAY",
    "a",
    "b"
  ]

  test "the fixture is what Lotus makes of the corpus" do
    # As JSON has it, so it compares with the committed file.
    built = build() |> Jason.encode!() |> Jason.decode!()

    if System.get_env("UPDATE_TOKENIZER_FIXTURE") do
      File.mkdir_p!(Path.dirname(@fixture))
      File.write!(@fixture, Jason.encode!(built, pretty: true) <> "\n")
    end

    committed = @fixture |> File.read!() |> Jason.decode!()

    assert committed["profiles"] == built["profiles"], """
    Lotus's lexical profiles changed. #{@update}
    """

    for {was, now} <- Enum.zip(committed["cases"], built["cases"]) do
      assert was == now, """
      Lotus reads #{inspect(now["text"])} (#{now["dialect"]}) differently:

          fixture: #{inspect(was["regions"])}
          Lotus:   #{inspect(now["regions"])}

      #{@update}
      """
    end

    assert length(committed["cases"]) == length(built["cases"]), @update

    assert committed["json_templates"] == built["json_templates"], """
    Lotus reads a JSON template differently. #{@update}
    """
  end

  defp build do
    texts = @corpus ++ random_texts()

    %{
      "profiles" =>
        Map.new(@dialects, fn {dialect, language} ->
          {dialect, Map.from_struct(Profile.for_language(language))}
        end),
      "cases" =>
        for {dialect, language} <- @dialects, text <- texts do
          profile = Profile.for_language(language)
          tokens = Tokenizer.tokenize(text, profile)
          regions = regions(tokens)
          ^text = regions |> Enum.map_join(fn [_kind, raw] -> raw end)
          %{"dialect" => dialect, "text" => text, "regions" => regions}
        end,
      "json_templates" => Enum.map(@json_corpus ++ json_random_texts(), &json_template/1)
    }
  end

  # What Lotus makes of a JSON template: its variables, and whether it is a
  # JSON object with every block kept (each variable given) and with every
  # block dropped (none given), each variable bound to a value. The
  # Elasticsearch adapter binds a variable in code, or a string that is only
  # the variable, to the value's JSON literal, and one inside a longer
  # string to its text; the string `"x"` stands for the value, which keeps a
  # variable that names a key a valid key.
  defp json_template(text) do
    profile = Profile.for_language("json:elasticsearch")
    names = Lotus.Variables.extract_names(text, profile)
    given = Map.new(names, &{&1, "x"})

    %{
      "text" => text,
      "variables" => names,
      "kept" => json_object?(Lotus.Query.OptionalClause.process(text, given, profile), profile),
      "dropped" => json_object?(Lotus.Query.OptionalClause.process(text, %{}, profile), profile)
    }
  end

  defp json_object?(text, profile) do
    bound =
      text
      |> Tokenizer.tokenize(profile)
      |> Enum.map(fn
        {:variable, _name, _raw} -> {:code, ~S|"x"|}
        {:string, raw} -> {:string, bind_string(raw)}
        token -> token
      end)
      |> Tokenizer.to_string()

    match?({:ok, %{}}, Lotus.JSON.decode(bound))
  end

  defp bind_string(raw) do
    case Tokenizer.variables([{:string, raw}]) do
      [name] when raw == "\"{{" <> name <> "}}\"" ->
        ~S|"x"|

      _ ->
        [{:string, bound}] = Tokenizer.replace_variables([{:string, raw}], fn _ -> "x" end)
        bound
    end
  end

  # The tokens as [kind, raw text], code runs merged: what both tokenizers
  # agree on, whatever the size of their code tokens.
  defp regions(tokens) do
    tokens |> Enum.flat_map(&region/1) |> merge_code()
  end

  defp region({:code, raw}), do: [["code", raw]]
  defp region({:comment, raw}), do: [["comment", raw]]
  defp region({:string, raw}), do: [["string", raw]]
  defp region({:identifier, raw}), do: [["identifier", raw]]
  defp region({:variable, _name, raw}), do: [["variable", raw]]

  defp region({:block, inner}),
    do: [["block_open", "[["]] ++ Enum.flat_map(inner, &region/1) ++ [["block_close", "]]"]]

  defp merge_code([["code", a], ["code", b] | rest]), do: merge_code([["code", a <> b] | rest])
  defp merge_code([region | rest]), do: [region | merge_code(rest)]
  defp merge_code([]), do: []

  # A fixed sequence, the same on every Elixir and OTP release (`:rand`
  # and `Enum.random/1` promise no such thing), so the fixture only
  # changes when Lotus does.
  defp random_texts do
    alphabet = List.to_tuple(@alphabet)

    {texts, _state} =
      Enum.map_reduce(1..@random_cases, 0x2545F491, fn _case, state ->
        {length, state} = next(state, 24)

        {pieces, state} =
          Enum.map_reduce(0..length, state, fn _piece, state ->
            {index, state} = next(state, tuple_size(alphabet))
            {elem(alphabet, index), state}
          end)

        {Enum.join(pieces), state}
      end)

    texts
  end

  # Random JSON-ish texts, from the same fixed sequence as random_texts/0.
  defp json_random_texts do
    alphabet =
      List.to_tuple(
        ~w({ } [ ] [[ ]] {{ }} : , " \\ x 1 -1 true null) ++
          [~S|"a"|, ~S|"{{v}}"|, "{{v}}", " ", "\n", ~S|"x{{w}}y"|]
      )

    {texts, _state} =
      Enum.map_reduce(1..200, 0x1F2E3D4C, fn _case, state ->
        {length, state} = next(state, 16)

        {pieces, state} =
          Enum.map_reduce(0..length, state, fn _piece, state ->
            {index, state} = next(state, tuple_size(alphabet))
            {elem(alphabet, index), state}
          end)

        {"{" <> Enum.join(pieces) <> "}", state}
      end)

    texts
  end

  # xorshift32: the next state, and a number below `bound` from it.
  defp next(state, bound) do
    state = bxor(state, state <<< 13 &&& 0xFFFFFFFF)
    state = bxor(state, state >>> 17)
    state = bxor(state, state <<< 5 &&& 0xFFFFFFFF)
    {rem(state, bound), state}
  end
end
