defmodule Lotus.Web.Branding do
  @moduledoc false

  # How the dashboard names and shows itself. Only Lotus Pro brands it: the
  # free version is always Lotus, and the router takes no branding options.
  # With Pro installed, `Lotus.Web.Pro.branding/1` asks it for the request's
  # branding, which may also give a theme and colours over the router's.
  # The footer of a public dashboard always says "Powered by Lotus", with
  # Pro too. Pro may also give a favicon, a font (and the stylesheet that
  # loads it), how round the corners are, and the workspace's language.

  import Phoenix.Component, only: [assign: 3]

  alias Lotus.Web.{Pro, Theme}

  defstruct product_name: "Lotus",
            logo: nil,
            assistant_name: nil,
            favicon: nil,
            font: nil,
            font_url: nil,
            radius: nil

  @type t :: %__MODULE__{
          product_name: String.t(),
          logo: String.t() | nil,
          assistant_name: String.t() | nil,
          favicon: String.t() | nil,
          font: String.t() | nil,
          font_url: String.t() | nil,
          radius: radius() | nil
        }

  @typedoc "How round the corners are: none, small, the default, or large."
  @type radius :: :none | :small | :medium | :large

  # The `--lotus-radius-*` steps of each radius, from sm to xl.
  @radii %{
    none: ["0", "0", "0", "0", "0"],
    small: ["0.125rem", "0.125rem", "0.125rem", "0.25rem", "0.25rem"],
    medium: ["0.125rem", "0.25rem", "0.375rem", "0.5rem", "0.75rem"],
    large: ["0.25rem", "0.375rem", "0.5rem", "0.75rem", "1rem"]
  }

  @doc "The Lotus branding."
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc """
  Asks the bridge for the branding of the request `info` describes and
  assigns it as `:branding`, with its theme and colours over the router's.
  What the bridge gives that is not valid is ignored.
  """
  @spec assign_branding(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def assign_branding(socket, info) do
    given = Pro.branding(info)
    %{themes: themes, theme_colors: colors} = socket.assigns

    socket
    |> assign(:branding, build(given))
    |> assign(:theme, theme(given, themes) || socket.assigns.theme)
    |> assign(:theme_colors, Map.merge(colors, theme_colors(given)))
    |> assign_locale(given[:locale])
  end

  # The workspace's language, unless the host chose one for the person
  # (`Lotus.Web.Locale`). Only a language Lotus or the app speaks
  # (`Lotus.Web.Translations`).
  defp assign_locale(socket, locale) when is_binary(locale) do
    if is_nil(socket.assigns[:lotus_locale]) and
         locale in Lotus.Web.Translations.known_locales() do
      Lotus.Web.Translations.put_locale(locale)
      assign(socket, :lotus_locale, locale)
    else
      socket
    end
  end

  defp assign_locale(socket, _locale), do: socket

  @doc """
  The CSS of the branding's font and corners, over every theme, or `nil`
  when it has neither. The font was checked when the branding was built,
  so it is safe to put in a style element.
  """
  @spec css(t() | nil) :: String.t() | nil
  def css(%__MODULE__{font: font, radius: radius}) when not is_nil(font) or not is_nil(radius) do
    font = if font, do: ["--lotus-font-sans: #{font};"], else: []

    radius =
      if radius do
        ~w(sm default md lg xl)
        |> Enum.zip(@radii[radius])
        |> Enum.map(fn
          {"default", value} -> "--lotus-radius: #{value};"
          {step, value} -> "--lotus-radius-#{step}: #{value};"
        end)
      else
        []
      end

    ":root[data-lotus-theme] { #{Enum.join(font ++ radius, " ")} }"
  end

  def css(_branding), do: nil

  defp build(given) do
    %__MODULE__{
      product_name: text(given[:product_name]) || "Lotus",
      logo: logo(given[:logo]),
      assistant_name: text(given[:assistant_name]),
      favicon: logo(given[:favicon]),
      font: font(given[:font]),
      font_url: stylesheet(given[:font_url]),
      radius: if(given[:radius] in Map.keys(@radii), do: given[:radius])
    }
  end

  # A CSS font family list, such as `"Acme Sans", system-ui, sans-serif`:
  # names, commas and spaces only, so nothing else can reach the style
  # element. Quotes are dropped (`Acme Sans` is the same family unquoted),
  # since the style element would show them escaped.
  defp font(font) when is_binary(font) do
    font = font |> String.replace(["\"", "'"], "") |> String.trim()

    if font =~ ~r/\A[\p{L}_-][\p{L}\p{N} _-]*(, *[\p{L}_-][\p{L}\p{N} _-]*)*\z/u and
         String.length(font) <= 200,
       do: font
  end

  defp font(_font), do: nil

  # The stylesheet that loads the font, such as Google Fonts': https only.
  defp stylesheet(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> url
      _other -> nil
    end
  end

  defp stylesheet(_url), do: nil

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp text(_value), do: nil

  # An image URL: https, http, or a path on the host. Anything else (a
  # `javascript:` or `data:` URL) is ignored.
  defp logo(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["https", "http"] and is_binary(host) -> url
      %URI{scheme: nil, host: nil, path: "/" <> _} -> url
      _other -> nil
    end
  end

  defp logo(_url), do: nil

  defp theme(given, themes) do
    if given[:theme] in themes, do: given[:theme]
  end

  defp theme_colors(given) do
    colors = given[:theme_colors]
    if is_map(colors) and Theme.valid_colors?(colors), do: colors, else: %{}
  end
end
