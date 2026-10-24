defmodule Lotus.Web.Branding do
  @moduledoc false

  # How the dashboard names and shows itself. Only Lotus Pro brands it: the
  # free version is always Lotus, and the router takes no branding options.
  # With Pro installed, `Lotus.Web.Pro.branding/1` asks it for the request's
  # branding, which may also give a theme and colours over the router's.
  # The footer of a public dashboard always says "Powered by Lotus", with
  # Pro too.

  import Phoenix.Component, only: [assign: 3]

  alias Lotus.Web.{Pro, Theme}

  defstruct product_name: "Lotus", logo: nil, assistant_name: nil

  @type t :: %__MODULE__{
          product_name: String.t(),
          logo: String.t() | nil,
          assistant_name: String.t() | nil
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
  end

  defp build(given) do
    %__MODULE__{
      product_name: text(given[:product_name]) || "Lotus",
      logo: logo(given[:logo]),
      assistant_name: text(given[:assistant_name])
    }
  end

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
