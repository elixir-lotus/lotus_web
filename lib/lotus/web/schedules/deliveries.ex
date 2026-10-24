defmodule Lotus.Web.Schedules.Deliveries do
  @moduledoc false

  # The destinations of a report or an alert: a form for each, drawn from
  # the channel's spec (`Lotus.Delivery.channel_specs/0`: its fields, formats
  # and whether it can send in this app), and the drafts they edit.
  #
  # A draft destination is a map of strings, as the form posts it:
  #
  #   * `"channel"`, `"format"`;
  #   * `"values"`: the channel's fields by key; an email list's is a list;
  #   * `"pending"`: the address still being typed in an email list;
  #   * `"json"`: the settings of a channel that does not describe them;
  #   * `"extra"`: what the saved settings hold that the form does not show
  #     (a webhook's other headers), kept as it was.

  use Lotus.Web, :html

  ## Specs

  @doc "The channels, as the editor shows them, with their text translated."
  def specs do
    Lotus.Delivery.channel_specs()
    |> Enum.map(&translate/1)
    |> Enum.sort_by(&order/1)
  end

  # The built-in channels first, the others after.
  defp order(%{name: "email"}), do: {0, ""}
  defp order(%{name: "slack"}), do: {1, ""}
  defp order(%{name: "webhook"}), do: {2, ""}
  defp order(spec), do: {3, String.downcase(spec.label)}

  @doc "The spec of a channel, or one for a channel that is gone."
  def spec(specs, name) do
    Enum.find(specs, &(&1.name == name)) ||
      %{
        name: name,
        label: name,
        settings: nil,
        formats: [],
        available: {:error, gettext("This channel is no longer set up.")}
      }
  end

  # The built-in channels' words in the page's language.
  defp translate(%{name: "webhook"} = spec) do
    %{
      spec
      | label: gettext("Webhook"),
        settings:
          translate_settings(spec.settings, %{
            "url" =>
              {gettext("URL"),
               gettext(
                 "Lotus POSTs JSON here, with the results attached. Any 2xx answer is a delivery."
               )},
            "authorization" =>
              {gettext("Authorization header"),
               gettext("Sent as the authorization header, for a token the receiver checks.")}
          })
    }
  end

  defp translate(%{name: "slack"} = spec) do
    %{
      spec
      | label: "Slack",
        settings:
          translate_settings(spec.settings, %{
            "webhook_url" =>
              {gettext("Incoming webhook URL"),
               gettext(
                 "In Slack, create an app, turn on incoming webhooks and add one to the channel to post in."
               )}
          })
    }
  end

  defp translate(%{name: "email"} = spec) do
    %{
      spec
      | label: gettext("Email"),
        settings:
          translate_settings(spec.settings, %{
            "to" => {gettext("Recipients"), gettext("Press Enter after each address.")},
            "subject" =>
              {gettext("Subject"), gettext("An alert's starts with [Alert] or [Recovered].")}
          })
    }
    |> put_placeholder("subject", gettext("The report's name"))
  end

  defp translate(spec), do: spec

  defp translate_settings(nil, _words), do: nil

  defp translate_settings(settings, words) do
    Enum.map(settings, fn setting ->
      case Map.get(words, setting.key) do
        {label, help} -> %{setting | label: label} |> Map.put(:help, help)
        nil -> setting
      end
    end)
  end

  defp put_placeholder(%{settings: settings} = spec, key, placeholder) when is_list(settings) do
    %{
      spec
      | settings:
          Enum.map(
            settings,
            &if(&1.key == key, do: Map.put(&1, :placeholder, placeholder), else: &1)
          )
    }
  end

  defp put_placeholder(spec, _key, _placeholder), do: spec

  @doc """
  Whether a channel's format is a choice: Slack posts a preview of the
  rows, and attaches no file.
  """
  def format_choice?(%{name: "slack"}), do: false
  def format_choice?(%{formats: formats}), do: length(formats) > 1

  ## Drafts

  @doc "A new destination on `channel`."
  def new(spec) do
    format = if "csv" in spec.formats, do: "csv", else: List.first(spec.formats)

    values =
      for setting <- spec.settings || [], into: %{} do
        {setting.key, if(setting.type == :email_list, do: [], else: "")}
      end

    %{
      "channel" => spec.name,
      "format" => format,
      "values" => values,
      "pending" => %{},
      "json" => "",
      "extra" => %{}
    }
  end

  @doc "The draft of a saved delivery."
  def from_delivery(delivery, specs) do
    spec = spec(specs, delivery.channel)
    config = delivery.config || %{}

    {values, extra} =
      case spec.settings do
        nil ->
          {%{}, %{}}

        settings ->
          keys = Enum.map(settings, & &1.key)

          values =
            for setting <- settings, into: %{} do
              {setting.key, value(setting, config[setting.key])}
            end

          {values, Map.drop(config, keys)}
      end

    {values, extra} = authorization_from_headers(delivery.channel, values, extra)

    %{
      "channel" => delivery.channel,
      "format" => delivery.format,
      "values" => values,
      "pending" => %{},
      "json" =>
        if(spec.settings == nil and config != %{}, do: Lotus.JSON.encode!(config), else: ""),
      "extra" => extra
    }
  end

  defp value(%{type: :email_list}, list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp value(%{type: :email_list}, _value), do: []
  defp value(_setting, value) when is_binary(value), do: value
  defp value(_setting, nil), do: ""
  defp value(_setting, value), do: to_string(value)

  # A webhook saved with an authorization header shows it in its field.
  defp authorization_from_headers("webhook", %{"authorization" => ""} = values, extra) do
    headers = extra["headers"] || %{}

    case headers["authorization"] || headers["Authorization"] do
      nil ->
        {values, extra}

      value ->
        headers = Map.drop(headers, ["authorization", "Authorization"])

        extra =
          if headers == %{},
            do: Map.delete(extra, "headers"),
            else: Map.put(extra, "headers", headers)

        {%{values | "authorization" => value}, extra}
    end
  end

  defp authorization_from_headers(_channel, values, extra), do: {values, extra}

  @doc "A draft destination with the form's params merged in."
  def merge(delivery, params) do
    values =
      case params["values"] do
        %{} = posted ->
          Map.merge(
            delivery["values"],
            Map.new(posted, fn {key, value} ->
              {key, posted_value(delivery["values"][key], value)}
            end)
          )

        _none ->
          delivery["values"]
      end

    delivery
    |> Map.merge(Map.take(params, ["format", "json"]))
    |> Map.put("values", values)
    |> Map.put("pending", Map.merge(delivery["pending"] || %{}, params["pending"] || %{}))
  end

  # An email list posts its addresses joined by commas, from the tag input.
  defp posted_value(previous, value) when is_list(previous) and is_binary(value),
    do: addresses(value)

  defp posted_value(_previous, value) when is_binary(value), do: value
  defp posted_value(previous, _value), do: previous

  defp addresses(text) do
    text
    |> String.split(~r/[\s,;]+/, trim: true)
    |> Enum.uniq()
  end

  @doc "Removes an address from a destination's email list."
  def remove_address(delivery, key, address) do
    update_in(delivery, ["values", key], &List.delete(&1 || [], address))
  end

  @doc "The delivery's attributes: `{:ok, attrs}` or `{:error, message}`."
  def to_attrs(delivery, specs) do
    spec = spec(specs, delivery["channel"])

    with {:ok, config} <- config(delivery, spec) do
      {:ok, %{channel: delivery["channel"], format: delivery["format"], config: config}}
    end
  end

  defp config(delivery, %{settings: nil}) do
    case String.trim(delivery["json"] || "") do
      "" ->
        {:ok, %{}}

      json ->
        case Lotus.JSON.decode(json) do
          {:ok, %{} = config} -> {:ok, config}
          _other -> {:error, gettext("A destination's settings must be a JSON object")}
        end
    end
  end

  defp config(delivery, %{settings: settings}) do
    config =
      Enum.reduce(settings, delivery["extra"] || %{}, fn setting, config ->
        case setting_value(setting, delivery) do
          nil -> Map.delete(config, setting.key)
          value -> Map.put(config, setting.key, value)
        end
      end)

    {:ok, config}
  end

  # An email list takes the address still being typed, too.
  defp setting_value(%{type: :email_list, key: key}, delivery) do
    pending = addresses(get_in(delivery, ["pending", key]) || "")

    case Enum.uniq((delivery["values"][key] || []) ++ pending) do
      [] -> nil
      list -> list
    end
  end

  defp setting_value(%{key: key}, delivery) do
    case String.trim(delivery["values"][key] || "") do
      "" -> nil
      value -> value
    end
  end

  @doc "What a destination is, in a few words: the summary beside the form."
  def label(%{"channel" => "webhook"} = delivery, specs) do
    case URI.parse(get_in(delivery, ["values", "url"]) || "") do
      %URI{host: host} when is_binary(host) and host != "" -> host <> format_label(delivery)
      _ -> spec(specs, "webhook").label <> format_label(delivery)
    end
  end

  def label(%{"channel" => "email"} = delivery, _specs) do
    case get_in(delivery, ["values", "to"]) || [] do
      [] -> gettext("Email, to no one yet")
      [one] -> one
      many -> ngettext("1 recipient", "%{count} recipients", length(many))
    end
  end

  def label(%{"channel" => channel} = delivery, specs) do
    spec = spec(specs, channel)
    if format_choice?(spec), do: spec.label <> format_label(delivery), else: spec.label
  end

  defp format_label(%{"format" => format}) when is_binary(format),
    do: " (#{String.upcase(format)})"

  defp format_label(_delivery), do: ""

  ## The form

  attr(:id, :string, required: true)
  attr(:index, :integer, required: true)
  attr(:delivery, :map, required: true)
  attr(:spec, :map, required: true)

  attr(:test, :any,
    default: nil,
    doc: "the last test: `:sending`, `:sent` or `{:error, message}`"
  )

  attr(:target, :any, required: true)

  @doc "A destination's card: its channel, format and fields, and its test."
  def destination(assigns) do
    ~H"""
    <div id={@id} class="rounded-lg border border-gray-200 dark:border-gray-700">
      <input type="hidden" name={"draft[deliveries][#{@index}][channel]"} value={@delivery["channel"]} />
      <div class="flex flex-wrap items-center gap-3 border-b border-gray-100 px-3 py-2 dark:border-gray-700">
        <.channel_icon name={@spec.name} class="h-7 w-7" />
        <span class="text-sm font-medium text-gray-900 dark:text-white"><%= @spec.label %></span>
        <div class="flex-1"></div>
        <div
          :if={format_choice?(@spec)}
          class="inline-flex rounded-md bg-gray-100 p-0.5 dark:bg-gray-900"
          role="radiogroup"
          aria-label={gettext("Format")}
        >
          <label
            :for={format <- @spec.formats}
            class={[
              "cursor-pointer rounded px-2.5 py-1 font-mono text-xs uppercase",
              @delivery["format"] == format && "bg-white text-gray-900 shadow-sm dark:bg-gray-700 dark:text-white",
              @delivery["format"] != format && "text-gray-500 hover:text-gray-800 dark:text-gray-400"
            ]}
          >
            <input type="radio" name={"draft[deliveries][#{@index}][format]"} value={format} checked={@delivery["format"] == format} class="sr-only" />
            <%= format %>
          </label>
        </div>
        <input :if={not format_choice?(@spec)} type="hidden" name={"draft[deliveries][#{@index}][format]"} value={@delivery["format"]} />
        <button
          type="button"
          id={"test-delivery-#{@index}"}
          phx-click="test_delivery"
          phx-value-index={@index}
          phx-target={@target}
          disabled={@test == :sending or match?({:error, _}, @spec.available)}
          title={gettext("Send sample results here now, to check the settings")}
          class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-gray-200 hover:bg-gray-50 hover:text-gray-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-gray-300 dark:ring-gray-600 dark:hover:bg-gray-700"
        >
          <Icons.send class="h-3.5 w-3.5" />
          <%= if @test == :sending, do: gettext("Sending…"), else: gettext("Send a test") %>
        </button>
        <button
          type="button"
          id={"remove-delivery-#{@index}"}
          phx-click="remove_delivery"
          phx-value-index={@index}
          phx-target={@target}
          aria-label={gettext("Remove this destination")}
          title={gettext("Remove this destination")}
          class="rounded-md p-1.5 text-gray-400 hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-950/40"
        >
          <Icons.trash class="h-4 w-4" />
        </button>
      </div>

      <div class="space-y-3 p-3">
        <.test_result id={"test-delivery-#{@index}-result"} test={@test} />
        <p
          :if={match?({:error, _}, @spec.available)}
          class="flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 text-xs text-amber-800 dark:bg-amber-950/30 dark:text-amber-300"
        >
          <Icons.exclamation_triangle class="mt-0.5 h-4 w-4 shrink-0" />
          <span><%= gettext("This channel cannot send yet: %{reason}", reason: elem(@spec.available, 1)) %></span>
        </p>

        <%= if @spec.settings do %>
          <.field
            :for={setting <- @spec.settings}
            setting={setting}
            value={@delivery["values"][setting.key]}
            name={"draft[deliveries][#{@index}][values][#{setting.key}]"}
            pending_name={"draft[deliveries][#{@index}][pending][#{setting.key}]"}
            pending={get_in(@delivery, ["pending", setting.key]) || ""}
            id={"#{@id}-#{setting.key}"}
            index={@index}
            target={@target}
          />
        <% else %>
          <label class="block">
            <span class="mb-1 block text-xs font-medium text-gray-700 dark:text-gray-300"><%= gettext("Settings, as JSON") %></span>
            <textarea
              name={"draft[deliveries][#{@index}][json]"}
              rows="3"
              placeholder="{}"
              class={[input_class(), "font-mono text-xs"]}
            ><%= @delivery["json"] %></textarea>
            <span class="mt-1 block text-xs text-gray-500 dark:text-gray-400">
              <%= gettext("What the %{channel} channel needs; its documentation lists them.", channel: @spec.label) %>
            </span>
          </label>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:test, :any, required: true)

  defp test_result(%{test: :sent} = assigns) do
    ~H"""
    <p id={@id} class="flex items-center gap-2 rounded-md bg-green-50 px-3 py-2 text-xs text-green-800 dark:bg-green-950/30 dark:text-green-300">
      <Icons.check class="h-4 w-4 shrink-0" />
      <%= gettext("Test sent. Check that it arrived.") %>
    </p>
    """
  end

  defp test_result(%{test: {:error, message}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <p id={@id} class="flex items-start gap-2 rounded-md bg-red-50 px-3 py-2 text-xs text-red-700 dark:bg-red-950/30 dark:text-red-300">
      <Icons.exclamation_circle class="mt-0.5 h-4 w-4 shrink-0" />
      <span><%= gettext("The test was not sent: %{reason}", reason: @message) %></span>
    </p>
    """
  end

  defp test_result(assigns), do: ~H""

  attr(:setting, :map, required: true)
  attr(:value, :any, required: true)
  attr(:name, :string, required: true)
  attr(:pending_name, :string, required: true)
  attr(:pending, :string, required: true)
  attr(:id, :string, required: true)
  attr(:index, :integer, required: true)
  attr(:target, :any, required: true)

  defp field(%{setting: %{type: :email_list}} = assigns) do
    assigns = assign(assigns, :addresses, assigns.value || [])

    ~H"""
    <div>
      <.field_label setting={@setting} for={@id <> "-input"} />
      <input type="hidden" id={@id <> "-hidden"} name={@name} value={Enum.join(@addresses, ",")} phx-hook="DispatchChangeOnUpdate" />
      <div class="flex min-h-[2.5rem] flex-wrap items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-2 py-1.5 focus-within:border-pink-500 focus-within:ring-1 focus-within:ring-pink-500 dark:border-gray-600 dark:bg-gray-700">
        <span
          :for={{address, n} <- Enum.with_index(@addresses)}
          id={"#{@id}-chip-#{n}"}
          class="inline-flex items-center gap-1 rounded-md bg-pink-50 py-0.5 pl-2 pr-1 text-sm text-pink-800 ring-1 ring-pink-200 dark:bg-pink-900/30 dark:text-pink-200 dark:ring-pink-900/60"
        >
          <%= address %>
          <button
            type="button"
            phx-click="remove_address"
            phx-value-index={@index}
            phx-value-key={@setting.key}
            phx-value-address={address}
            phx-target={@target}
            aria-label={gettext("Remove %{address}", address: address)}
            class="rounded p-0.5 text-pink-500 hover:bg-pink-100 hover:text-pink-700 dark:hover:bg-pink-900/50"
          >
            <Icons.x_mark class="h-3 w-3" />
          </button>
        </span>
        <input
          type="email"
          id={@id <> "-input"}
          name={@pending_name}
          value={@pending}
          phx-hook="TagInput"
          data-hidden-id={@id <> "-hidden"}
          data-tag-count={length(@addresses)}
          placeholder={if @addresses == [], do: @setting[:placeholder], else: gettext("Add another…")}
          autocomplete="off"
          class="min-w-[12rem] flex-1 border-0 bg-transparent p-0.5 text-sm placeholder:text-gray-400 focus:ring-0 dark:text-white dark:placeholder:text-gray-500"
        />
      </div>
      <.field_help setting={@setting} />
    </div>
    """
  end

  defp field(%{setting: %{type: :select}} = assigns) do
    ~H"""
    <label class="block">
      <.field_label setting={@setting} />
      <select name={@name} id={@id} class={input_class()}>
        <option :for={{label, value} <- @setting[:options] || []} value={value} selected={@value == value}><%= label %></option>
      </select>
      <.field_help setting={@setting} />
    </label>
    """
  end

  defp field(%{setting: %{type: :textarea}} = assigns) do
    ~H"""
    <label class="block">
      <.field_label setting={@setting} />
      <textarea name={@name} id={@id} rows="3" placeholder={@setting[:placeholder]} class={input_class()}><%= @value %></textarea>
      <.field_help setting={@setting} />
    </label>
    """
  end

  defp field(assigns) do
    assigns =
      assign(
        assigns,
        :input_type,
        case assigns.setting.type do
          :secret -> "password"
          :url -> "url"
          _text -> "text"
        end
      )

    ~H"""
    <label class="block">
      <.field_label setting={@setting} />
      <input
        type={@input_type}
        id={@id}
        name={@name}
        value={@value}
        placeholder={@setting[:placeholder]}
        autocomplete={if @setting.type == :secret, do: "new-password", else: "off"}
        spellcheck="false"
        class={[input_class(), @setting.type in [:secret, :url] && "font-mono"]}
      />
      <.field_help setting={@setting} />
    </label>
    """
  end

  attr(:setting, :map, required: true)
  attr(:for, :string, default: nil)

  defp field_label(assigns) do
    ~H"""
    <span class="mb-1 block text-xs font-medium text-gray-700 dark:text-gray-300">
      <label :if={@for} for={@for}><%= @setting.label %></label><span :if={!@for}><%= @setting.label %></span>
      <span :if={not Map.get(@setting, :required, false)} class="font-normal text-gray-400"><%= gettext("optional") %></span>
    </span>
    """
  end

  attr(:setting, :map, required: true)

  defp field_help(assigns) do
    ~H"""
    <span :if={@setting[:help]} class="mt-1 block text-xs text-gray-500 dark:text-gray-400"><%= @setting.help %></span>
    """
  end

  attr(:specs, :list, required: true)
  attr(:target, :any, required: true)

  @doc "The channels to add a destination on, as tiles."
  def channel_picker(assigns) do
    ~H"""
    <div id="channel-picker" class="rounded-lg border border-gray-200 p-3 dark:border-gray-700">
      <p class="mb-2 text-xs font-medium text-gray-700 dark:text-gray-300"><%= gettext("Send to") %></p>
      <div class="grid gap-2 sm:grid-cols-3">
        <button
          :for={spec <- @specs}
          type="button"
          id={"add-#{spec.name}"}
          phx-click="add_delivery"
          phx-value-channel={spec.name}
          phx-target={@target}
          disabled={match?({:error, _}, spec.available)}
          class="group flex items-start gap-3 rounded-lg border border-gray-200 p-3 text-left transition enabled:hover:border-pink-300 enabled:hover:bg-pink-50/40 disabled:cursor-not-allowed disabled:opacity-60 dark:border-gray-700 dark:enabled:hover:bg-pink-950/20"
        >
          <.channel_icon name={spec.name} class="h-8 w-8" />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-gray-900 dark:text-white"><%= spec.label %></span>
            <span :if={spec.available == :ok} class="block text-xs text-gray-500 dark:text-gray-400"><%= channel_blurb(spec) %></span>
            <span :if={match?({:error, _}, spec.available)} class="block text-xs text-amber-700 dark:text-amber-400">
              <%= gettext("Not set up:") %> <%= elem(spec.available, 1) %>
            </span>
          </span>
        </button>
      </div>
      <button
        type="button"
        phx-click="cancel_add_delivery"
        phx-target={@target}
        class="mt-2 text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400"
      >
        <%= gettext("Cancel") %>
      </button>
    </div>
    """
  end

  defp channel_blurb(%{name: "email"}),
    do: gettext("Through your app's mailer, the results attached.")

  defp channel_blurb(%{name: "slack"}),
    do: gettext("A message in a channel, with the first rows.")

  defp channel_blurb(%{name: "webhook"}),
    do: gettext("JSON to a URL of yours, the results attached.")

  defp channel_blurb(_spec), do: ""

  attr(:name, :string, required: true)
  attr(:class, :string, default: "h-7 w-7")

  @doc "A channel's icon in a tile."
  def channel_icon(assigns) do
    ~H"""
    <span class={[
      "flex shrink-0 items-center justify-center rounded-md",
      @name == "email" && "bg-blue-50 text-blue-600 dark:bg-blue-900/30 dark:text-blue-300",
      @name == "slack" && "bg-purple-50 text-purple-600 dark:bg-purple-900/30 dark:text-purple-300",
      @name not in ["email", "slack"] && "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300",
      @class
    ]}>
      <Icons.envelope :if={@name == "email"} class="h-4 w-4" />
      <Icons.slack :if={@name == "slack"} class="h-4 w-4" />
      <Icons.link_icon :if={@name == "webhook"} class="h-4 w-4" />
      <Icons.send :if={@name not in ["email", "slack", "webhook"]} class="h-4 w-4" />
    </span>
    """
  end

  defp input_class,
    do:
      "w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:border-pink-500 focus:ring-1 focus:ring-pink-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-500"
end
