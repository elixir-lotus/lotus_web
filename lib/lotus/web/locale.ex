defmodule Lotus.Web.Locale do
  @moduledoc """
  `on_mount` hook that sets the dashboard locale.

  `Lotus.Web.Router.lotus_dashboard/2` adds this hook to the live session
  after the host's own `:on_mount` hooks, so a host never lists it. The hook
  reads `"lotus_locale"` from the session and falls back to the configured
  default locale. Write that key in a plug to choose the language:

      put_session(conn, :lotus_locale, "fr")
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    session
    |> Map.get("lotus_locale")
    |> normalize_locale()
    |> case do
      nil ->
        {:cont, socket}

      locale ->
        Gettext.put_locale(Lotus.Web.Gettext, locale)
        {:cont, assign(socket, :lotus_locale, locale)}
    end
  end

  def on_mount(_hook, _params, _session, socket), do: {:cont, socket}

  defp normalize_locale(locale) when is_binary(locale) do
    locale
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_locale(_locale), do: nil
end
