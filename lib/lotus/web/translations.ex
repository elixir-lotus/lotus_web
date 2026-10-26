defmodule Lotus.Web.Translations do
  @moduledoc """
  Your app's translations of Lotus, for a language Lotus does not ship or
  for wording of your own.

  Lotus Web ships English and French. Your app adds a language, or changes
  how a string reads, in its own Gettext backend, under the `lotus_web`
  domain (and `lotus_pro` for Lotus Pro's pages):

      # config/config.exs
      config :lotus_web, gettext: MyAppWeb.Gettext

  Copy Lotus's strings into your app, make a language's file, and
  translate it as you translate your app:

      $ mix lotus_web.gettext
      $ mix gettext.merge priv/gettext --locale es

  `mix lotus_web.gettext` writes `priv/gettext/lotus_web.pot` (and
  `lotus_pro.pot` with Lotus Pro), and runs again after an upgrade to bring
  in new strings. Your app's `mix gettext.extract` leaves those files alone.

  A string your app translates is used wherever Lotus has no translation of
  its own: every string of a language Lotus does not ship, and every
  English string (Lotus's English is its source text). French and the other
  languages Lotus ships are changed through a pull request to Lotus, so that
  every app has them.

  Lotus's own backends take part with
  `use Lotus.Web.Translations, domain: "lotus_web"`, after
  `use Gettext.Backend`.
  """

  @doc false
  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)

    quote do
      @impl Gettext.Backend
      def handle_missing_translation(locale, domain, msgctxt, msgid, bindings) do
        with :none <-
               Lotus.Web.Translations.host_translation(
                 __MODULE__,
                 unquote(domain),
                 [locale, msgctxt, msgid, bindings]
               ) do
          super(locale, domain, msgctxt, msgid, bindings)
        end
      end

      @impl Gettext.Backend
      def handle_missing_plural_translation(
            locale,
            domain,
            msgctxt,
            msgid,
            msgid_plural,
            n,
            bindings
          ) do
        with :none <-
               Lotus.Web.Translations.host_translation(
                 __MODULE__,
                 unquote(domain),
                 [locale, msgctxt, msgid, msgid_plural, n, bindings]
               ) do
          super(locale, domain, msgctxt, msgid, msgid_plural, n, bindings)
        end
      end
    end
  end

  @doc "Your app's Gettext backend (`config :lotus_web, gettext:`), or `nil`."
  @spec backend() :: module() | nil
  def backend, do: Application.get_env(:lotus_web, :gettext)

  @doc false
  # The host's translation of a string Lotus has none of, in the host's
  # `domain`: what the host's backend answers when it has one, else `:none`.
  def host_translation(lotus_backend, domain, [locale | rest]) do
    with host when is_atom(host) and not is_nil(host) and host != lotus_backend <- backend(),
         true <- Code.ensure_loaded?(host) do
      case lookup(host, domain, locale, rest) do
        {:default, _string} -> :none
        result -> result
      end
    else
      _none -> :none
    end
  end

  defp lookup(host, domain, locale, [msgctxt, msgid, bindings]),
    do: host.lgettext(locale, domain, msgctxt, msgid, bindings)

  defp lookup(host, domain, locale, [msgctxt, msgid, msgid_plural, n, bindings]),
    do: host.lngettext(locale, domain, msgctxt, msgid, msgid_plural, n, bindings)

  @doc """
  The languages Lotus can show: those it ships and those of your app's
  backend.
  """
  @spec known_locales() :: [String.t()]
  def known_locales do
    host =
      case backend() do
        nil -> []
        host -> Gettext.known_locales(host)
      end

    Enum.uniq(Gettext.known_locales(Lotus.Web.Gettext) ++ host)
  end

  @doc """
  Shows Lotus in `locale` in this process: Lotus Web's strings, Lotus Pro's,
  and your app's in the same process.
  """
  @spec put_locale(String.t()) :: :ok
  def put_locale(locale) when is_binary(locale) do
    Gettext.put_locale(locale)
    Gettext.put_locale(Lotus.Web.Gettext, locale)
    :ok
  end
end
