defmodule Lotus.Web.TranslationsTest do
  @moduledoc """
  An app translates Lotus in its own Gettext backend
  (`config :lotus_web, gettext:`): a language Lotus does not ship, and its
  own English wording. `mix lotus_web.gettext` copies Lotus's strings into
  it.
  """
  use Lotus.Web.Case, async: false

  use Gettext, backend: Lotus.Web.Gettext

  import Phoenix.LiveViewTest

  alias Lotus.Web.Test.HostGettext
  alias Lotus.Web.Translations

  defp with_host(backend \\ HostGettext) do
    Application.put_env(:lotus_web, :gettext, backend)
    on_exit(fn -> Application.delete_env(:lotus_web, :gettext) end)
  end

  defp in_locale(locale, fun) do
    previous = Gettext.get_locale(Lotus.Web.Gettext)
    Translations.put_locale(locale)

    try do
      fun.()
    after
      Translations.put_locale(previous)
      Process.delete(Gettext)
    end
  end

  describe "without the app's backend" do
    test "Lotus speaks its own languages, and English otherwise" do
      assert in_locale("fr", fn -> gettext("Queries") end) == "Requêtes"
      assert in_locale("es", fn -> gettext("Queries") end) == "Queries"
      assert Translations.known_locales() |> Enum.sort() == ["en", "fr"]
    end
  end

  describe "with the app's backend" do
    setup do
      with_host()
    end

    test "a language Lotus does not ship comes from the app" do
      assert in_locale("es", fn -> gettext("Queries") end) == "Consultas"

      assert in_locale("es", fn ->
               ngettext("1 recipient", "%{count} recipients", 3)
             end) == "3 destinatarios"

      # A string the app has not translated stays Lotus's English.
      assert in_locale("es", fn -> gettext("Refresh") end) == "Refresh"
    end

    test "the app words Lotus's English its own way" do
      assert in_locale("en", fn -> gettext("Dashboards") end) == "Boards"
      assert in_locale("en", fn -> gettext("Queries") end) == "Queries"
    end

    test "Lotus's own translations stay Lotus's" do
      assert in_locale("fr", fn -> gettext("Queries") end) == "Requêtes"
    end

    test "the app's languages are known, so a workspace may pick one" do
      assert "es" in Translations.known_locales()
    end

    test "the dashboard shows the app's language" do
      conn = Plug.Test.init_test_session(build_conn(), %{"lotus_locale" => "es"})
      {:ok, _live, html} = live(conn, "/lotus")

      assert html =~ "Consultas"
      assert html =~ "Paneles"
    end

    test "Lotus's own backend as the app's is ignored" do
      with_host(Lotus.Web.Gettext)
      assert in_locale("es", fn -> gettext("Queries") end) == "Queries"
    end
  end

  describe "mix lotus_web.gettext" do
    @tag :tmp_dir
    test "copies Lotus's strings into the app, for its extract to keep", %{tmp_dir: dir} do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      Mix.Tasks.LotusWeb.Gettext.run(["--priv", dir])

      pot = File.read!(Path.join(dir, "lotus_web.pot"))
      assert pot =~ ~s(msgid "Queries")
      assert pot =~ "#, elixir-format"
      refute pot =~ "elixir-autogen"
      refute pot =~ "#: lib/"

      # It reads as a template Gettext can merge into a language's file.
      assert {:ok, %Expo.Messages{messages: [_ | _]}} = Expo.PO.parse_string(pot)
    end
  end
end
