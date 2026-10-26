defmodule Lotus.Web.TokenizerConformanceTest do
  # The editor's tokenizer (assets/js/lib/languages/sql/tokenizer.js) reads
  # SQL as Lotus's (`Lotus.Query.Tokenizer`) does. This test writes what
  # Lotus makes of a corpus of statements, per dialect, to a fixture the JS
  # tests hold the editor's tokenizer to (tokenizer_conformance.test.js).
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
    {"ansi", "sql"}
  ]

  # Statements at the edges of each dialect's rules.
  @corpus [
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
        end
    }
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

  # xorshift32: the next state, and a number below `bound` from it.
  defp next(state, bound) do
    state = bxor(state, state <<< 13 &&& 0xFFFFFFFF)
    state = bxor(state, state >>> 17)
    state = bxor(state, state <<< 5 &&& 0xFFFFFFFF)
    {rem(state, bound), state}
  end
end
