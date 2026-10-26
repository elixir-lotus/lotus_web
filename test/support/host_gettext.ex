defmodule Lotus.Web.Test.HostGettext do
  @moduledoc false
  # An app's own Gettext backend, with its translations of Lotus in the
  # `lotus_web` domain (`Lotus.Web.Translations`).
  use Gettext.Backend, otp_app: :lotus_web, priv: "test/support/gettext"
end
