defmodule Lotus.Web.Theme do
  @moduledoc """
  The themes of the dashboard and the colour tokens a host can override.

  A theme is a set of `--lotus-*` CSS custom properties (see
  `assets/css/app.css`); the Tailwind classes of the dashboard read them.
  The theme is picked with the `:theme` option of
  `Lotus.Web.Router.lotus_dashboard/2`, and single colours are overridden
  with `:theme_colors`. See the Theming guide.
  """

  @names [:lotus, :sumi]

  @steps ~w(50 100 200 300 400 500 600 700 800 900 950)

  @scales ~w(gray zinc pink indigo rose)

  @singles ~w(white black canvas canvas-dark editor-light editor-dark input-dark
              text-light text-dark logo-ink logo-ink-dark logo-petal)

  @tokens for(scale <- @scales, step <- @steps, do: "#{scale}-#{step}") ++ @singles

  @hex ~r/\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/

  @typedoc "A built-in theme."
  @type name :: :lotus | :sumi

  @doc "The names of the built-in themes."
  @spec names() :: [name(), ...]
  def names, do: @names

  @doc "The colour tokens that `:theme_colors` accepts."
  @spec tokens() :: [String.t()]
  def tokens, do: @tokens

  @doc """
  Whether `colors` is a map from known tokens (strings or atoms) to hex
  colours such as `"#0ea5e9"` or `"#0af"`.
  """
  @spec valid_colors?(map()) :: boolean()
  def valid_colors?(colors) when is_map(colors) do
    Enum.all?(colors, fn {token, value} ->
      to_string(token) in @tokens and is_binary(value) and Regex.match?(@hex, value)
    end)
  end

  def valid_colors?(_colors), do: false

  @doc """
  The CSS that applies `colors` over every theme, or `nil` when there is
  nothing to override. The values were checked by `valid_colors?/1` when the
  router compiled, so they are safe to put in a style element.
  """
  @spec css(map() | nil) :: String.t() | nil
  def css(colors) when is_map(colors) and map_size(colors) > 0 do
    properties =
      colors
      |> Enum.filter(fn {token, value} ->
        to_string(token) in @tokens and is_binary(value) and Regex.match?(@hex, value)
      end)
      |> Enum.sort()
      |> Enum.map_join(" ", fn {token, value} -> "--lotus-#{token}: #{channels(value)};" end)

    ":root[data-lotus-theme] { #{properties} }"
  end

  def css(_colors), do: nil

  defp channels("#" <> <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>>),
    do: channels("#" <> r <> r <> g <> g <> b <> b)

  defp channels("#" <> hex) do
    hex
    |> String.to_integer(16)
    |> then(fn value ->
      [
        Bitwise.bsr(value, 16),
        value |> Bitwise.bsr(8) |> Bitwise.band(255),
        Bitwise.band(value, 255)
      ]
    end)
    |> Enum.join(" ")
  end
end
