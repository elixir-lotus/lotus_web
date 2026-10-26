defmodule Lotus.Web.Gettext do
  @moduledoc """
  Lotus Web's Gettext backend: its strings, in the `default` domain, with
  the translations Lotus ships in `priv/gettext/<locale>/LC_MESSAGES/default.po`.

  Your app adds a language, or changes a string's wording, in its own
  backend (`Lotus.Web.Translations`). Translations for every app are
  contributed with a pull request.
  """

  use Gettext.Backend, otp_app: :lotus_web
  use Lotus.Web.Translations, domain: "lotus_web"
end
