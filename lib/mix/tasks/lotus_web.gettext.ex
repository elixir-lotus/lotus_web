defmodule Mix.Tasks.LotusWeb.Gettext do
  @shortdoc "Copies Lotus's strings into your app, to translate them"
  @moduledoc """
  Copies the strings of Lotus Web, and of Lotus Pro when it is installed,
  into your app's Gettext directory, to translate them as your app's own
  (`Lotus.Web.Translations`):

      $ mix lotus_web.gettext
      $ mix gettext.merge priv/gettext --locale es

  It writes `lotus_web.pot` (and `lotus_pro.pot`), in place of the last
  copy; run it again after upgrading Lotus to bring in new strings, then
  `mix gettext.merge priv/gettext`. Your app's `mix gettext.extract` leaves
  these files alone.

  Then tell Lotus which backend has them:

      config :lotus_web, gettext: MyAppWeb.Gettext

  ## Options

    * `--priv` - the directory of your Gettext backend's files
      (default: `priv/gettext`)
  """

  use Mix.Task

  # Each Lotus app with strings, and the domain your app keeps them in.
  @apps [lotus_web: "lotus_web", lotus_pro: "lotus_pro"]

  @impl Mix.Task
  def run(args) do
    {opts, _args} = OptionParser.parse!(args, strict: [priv: :string])
    priv = opts[:priv] || "priv/gettext"
    File.mkdir_p!(priv)

    copied =
      for {app, domain} <- @apps,
          source = source(app),
          source && File.exists?(source) do
        target = Path.join(priv, "#{domain}.pot")
        File.write!(target, template(File.read!(source), domain))
        Mix.shell().info("* #{target}")
        target
      end

    if copied == [] do
      Mix.raise("Found no Lotus strings to copy. Is lotus_web a dependency of this project?")
    end

    Mix.shell().info("""

    Next, make or update a language's file, and translate it:

        mix gettext.merge #{priv} --locale es

    And point Lotus at your backend, if you have not:

        config :lotus_web, gettext: MyAppWeb.Gettext
    """)
  end

  defp source(app) do
    case :code.priv_dir(app) do
      {:error, :bad_name} -> nil
      dir -> Path.join([to_string(dir), "gettext", "default.pot"])
    end
  end

  @doc false
  # Lotus's template, as your app keeps it: Lotus's file references dropped
  # (they point into the dependency), and not flagged as extracted, so that
  # your app's `mix gettext.extract` does not take its strings for obsolete.
  def template(pot, domain) do
    body =
      pot
      |> String.split("\n")
      |> Enum.reject(&String.starts_with?(&1, "#:"))
      |> Enum.map(&unflag/1)
      |> Enum.reject(&(&1 == "#,"))
      |> Enum.join("\n")
      |> String.replace(~r/\A(#[^\n]*\n)*\n*/, "")

    """
    # Lotus's strings, copied by `mix lotus_web.gettext`: translate them in
    # each language's #{domain}.po (`mix gettext.merge`), and run the task
    # again after upgrading Lotus.
    #
    # The Lotus app sees them through `config :lotus_web, gettext:`.

    """ <> body
  end

  defp unflag("#, " <> flags) do
    kept =
      flags
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "elixir-autogen"))

    "#, " <> Enum.join(kept, ", ")
  end

  defp unflag(line), do: line
end
