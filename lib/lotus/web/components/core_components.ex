defmodule Lotus.Web.CoreComponents do
  @moduledoc """
  Core UI components for Lotus Web.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Lotus.Web.Components.Icons

  # Lotus Pro's content for the slot `name` (`Lotus.Web.Pro.render_slot/2`),
  # given `slot_assigns`. Nothing without Pro.
  #
  # The slots: `:nav` (the header), `:list_toolbar` (in the row of a list of
  # queries or dashboards, by its search, with the request and `:tab`),
  # `:query_badges` and `:dashboard_badges` (on each tile and row),
  # `:query_editor_header` and `:dashboard_header` (by the name of a saved
  # query or dashboard, with the request as `:info`,
  # `Lotus.Web.Pro.request_info/1`) and `:card_header`.
  @doc false
  attr(:name, :atom, required: true)
  attr(:slot_assigns, :map, default: %{})

  def pro_slot(assigns) do
    ~H"{Lotus.Web.Pro.render_slot(@name, @slot_assigns)}"
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr(:type, :string, default: nil)
  attr(:class, :string, default: nil)
  attr(:variant, :string, default: "default")
  attr(:rest, :global, include: ~w(disabled form name value))

  slot(:inner_block, required: true)

  def button(assigns) do
    assigns =
      assign_new(assigns, :variant_class, fn ->
        base_classes =
          case assigns.variant do
            "light" ->
              "rounded-md bg-white dark:bg-transparent px-3.5 py-2.5 text-sm font-semibold text-gray-900 dark:text-gray-100 shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-gray-600 hover:bg-gray-50 dark:hover:bg-white/10"

            _ ->
              "phx-submit-loading:opacity-75 rounded-md bg-pink-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-pink-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-pink-600"
          end

        # Add disabled styles
        base_classes <> " disabled:opacity-50 disabled:cursor-not-allowed"
      end)

    ~H"""
    <button type={@type} class={[@variant_class, @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               radio range search select multiselect tel text textarea time url week)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")

  attr(:rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)
  )

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600 dark:text-zinc-400">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 dark:border-zinc-600 dark:bg-input-dark text-text-light dark:text-text-dark focus:ring-0"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "radio", name: name, value: value} = assigns) do
    id = name <> "_" <> to_string(value)

    assigns =
      assigns
      |> assign(:id, id)
      |> assign_new(:checked, fn -> false end)

    ~H"""
    <label class="flex items-center cursor-pointer">
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="h-4 w-4 text-pink-600 focus:ring-0 border-gray-300 dark:border-gray-600 dark:bg-input-dark"
        {@rest}
      />
      <span :if={@label} class="ml-2 text-sm text-gray-700 dark:text-gray-300">
        {@label}
      </span>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
      <.live_component
        module={Lotus.Web.SelectComponent}
        id={@id || "#{@name}-select-plus"}
        name={@name}
        label={@label}
        value={@value}
        options={@options || []}
        prompt={@prompt}
        disabled={@rest[:disabled]}
        errors={@errors}
        {@rest}
      />
    """
  end

  def input(%{type: "multiselect"} = assigns) do
    ~H"""
      <.live_component
        module={Lotus.Web.MultiSelectComponent}
        id={@id || "#{@name}-multiselect-plus"}
        name={@name}
        label={@label}
        value={@value}
        options={@options || []}
        prompt={@prompt}
        disabled={@rest[:disabled]}
        errors={@errors}
        {@rest}
      />
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-text-light dark:text-text-dark dark:bg-input-dark focus:ring-0 sm:text-sm sm:leading-6 min-h-[6rem]",
          @errors == [] && "border-zinc-300 dark:border-zinc-600 focus:border-zinc-400 dark:focus:border-zinc-500",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-text-light dark:text-text-dark dark:bg-input-dark focus:ring-0 sm:text-sm sm:leading-6",
          @errors == [] && "border-zinc-300 dark:border-zinc-600 focus:border-zinc-400 dark:focus:border-zinc-500",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr(:for, :string, default: nil)
  slot(:inner_block, required: true)

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-text-light dark:text-text-dark">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <%!-- <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" /> --%>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  slot(:inner_block, required: true)

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/60 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 dark:ring-zinc-300/10 relative hidden rounded-2xl bg-white dark:bg-gray-800 p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40 text-gray-900 dark:text-gray-100"
                  aria-label="close"
                >
                  <Icons.x_mark class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a flash message.
  """
  attr(:flash, :map, required: true)
  attr(:kind, :atom, required: true)

  def flash(%{flash: flash, kind: kind} = assigns) do
    assigns = assign(assigns, :msg, Phoenix.Flash.get(flash, kind))

    ~H"""
    <%= if @msg do %>
      <div
        id={"flash-#{@kind}"}
        phx-hook="Flash"
        class={[
          "fixed bottom-4 right-4 p-4 z-50 shadow-lg max-w-md",
          @kind == :info && "border-l-4 border-blue-400 bg-blue-50 dark:border-blue-500 dark:bg-blue-500/10",
          @kind == :error && "border-l-4 border-yellow-400 bg-yellow-50 dark:border-yellow-500 dark:bg-yellow-500/10"
        ]}
      >
        <div class="flex items-center">
          <div class="shrink-0">
            <%= if @kind == :info do %>
              <Icons.information_circle class="size-5 text-blue-400 dark:text-blue-500" />
            <% else %>
              <Icons.exclamation_triangle class="size-5 text-yellow-400 dark:text-yellow-500" />
            <% end %>
          </div>
          <div class="ml-3 flex-1">
            <p class={[
              "text-sm",
              @kind == :info && "text-blue-700 dark:text-blue-300",
              @kind == :error && "text-yellow-700 dark:text-yellow-300"
            ]}>
              <%= @msg %>
            </p>
          </div>
          <div class="ml-auto pl-3">
            <button
              type="button"
              class="inline-flex p-1.5 text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-400 transition-colors"
              aria-label="Dismiss"
            >
              <Icons.x_mark class="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders a table with striped rows.

  ## Examples

      <.table id="results" rows={@results}>
        <:col :let={row} label="id">{row.id}</:col>
        <:col :let={row} label="name">{row.name}</:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:sticky_header, :boolean,
    default: false,
    doc: "if true, keeps header visible while body scrolls"
  )

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col slots"
  )

  slot :col, required: true do
    attr(:label, :string)
  end

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class={[
      "flow-root",
      @sticky_header && "h-full"
    ]}>
      <div class={[
        "-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8",
        @sticky_header && "overflow-y-auto h-full"
      ]}>
        <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
          <table class={[
            "relative min-w-full",
            !@sticky_header && "divide-y divide-gray-300 dark:divide-gray-600"
          ]}>
            <thead class={[
              @sticky_header && "sticky top-0 z-10 bg-white dark:bg-gray-800 shadow-[0_1px_0_0] shadow-gray-300 dark:shadow-gray-600"
            ]}>
              <tr>
                <th
                  :for={col <- @col}
                  scope="col"
                  class={[
                    "py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-text-light dark:text-text-dark sm:pl-3",
                    @sticky_header && "bg-white dark:bg-gray-800"
                  ]}
                >
                  {col[:label]}
                </th>
              </tr>
            </thead>
            <tbody
              id={@id}
              phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
              class="bg-white dark:bg-gray-800"
            >
              <tr
                :for={row <- @rows}
                id={@row_id && @row_id.(row)}
                class="even:bg-gray-50 dark:even:bg-gray-700"
              >
                <td
                  :for={col <- @col}
                  phx-click={@row_click && @row_click.(row)}
                  class="whitespace-nowrap py-4 pl-4 pr-3 text-sm text-text-light dark:text-text-dark sm:pl-3"
                >
                  {render_slot(col, @row_item.(row))}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the appearance menu: light, dark or system, and the theme (Lotus or
  Sumi). The trigger shows the icon of the chosen appearance.
  """
  attr(:themes, :list,
    default: [:lotus, :sumi],
    doc: "the themes on offer; with one, the menu offers no theme choice"
  )

  attr(:rest, :global)

  def theme_selector(assigns) do
    ~H"""
    <div class="relative" id="theme-selector" phx-hook="ThemeSelector" {@rest}>
      <button
        type="button"
        class="rounded-full p-2 text-gray-500 hover:text-gray-900 hover:bg-gray-100 dark:text-gray-400 dark:hover:text-gray-100 dark:hover:bg-gray-700 transition-colors duration-200"
        aria-label="Theme selector"
        data-dropdown-trigger
      >
        <Icons.sun class="h-5 w-5 theme-icon" data-theme="light" />
        <Icons.moon class="h-5 w-5 theme-icon hidden" data-theme="dark" />
        <Icons.monitor class="h-5 w-5 theme-icon hidden" data-theme="system" />
      </button>

      <div
        class="absolute right-0 top-full mt-2 w-48 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-md shadow-lg z-50 hidden"
        data-dropdown-menu
      >
        <div class="py-1">
          <p class="px-3 pt-1 pb-1 text-xs font-medium text-gray-500 dark:text-gray-400">
            Appearance
          </p>
          <button
            type="button"
            class="flex items-center w-full px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 aria-pressed:text-pink-600 dark:aria-pressed:text-pink-400 transition-colors"
            data-theme-option="light"
          >
            <Icons.sun class="h-4 w-4 mr-3" />
            Light
          </button>
          <button
            type="button"
            class="flex items-center w-full px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 aria-pressed:text-pink-600 dark:aria-pressed:text-pink-400 transition-colors"
            data-theme-option="dark"
          >
            <Icons.moon class="h-4 w-4 mr-3" />
            Dark
          </button>
          <button
            type="button"
            class="flex items-center w-full px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 aria-pressed:text-pink-600 dark:aria-pressed:text-pink-400 transition-colors"
            data-theme-option="system"
          >
            <Icons.monitor class="h-4 w-4 mr-3" />
            System
          </button>
        </div>
        <div :if={length(@themes) > 1} class="py-1 border-t border-gray-200 dark:border-gray-700">
          <p class="px-3 pt-1 pb-1 text-xs font-medium text-gray-500 dark:text-gray-400">
            Theme
          </p>
          <button
            :for={{palette, label, swatch} <- theme_options(@themes)}
            type="button"
            class="flex items-center w-full px-3 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 aria-pressed:text-pink-600 dark:aria-pressed:text-pink-400 transition-colors"
            data-palette-option={palette}
          >
            <span class={["h-3 w-3 mr-3 rounded-full ring-1 ring-black/10", swatch]}></span>
            {label}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp theme_options(themes) do
    Enum.filter(
      [{:lotus, "Lotus", "bg-[#ff8086]"}, {:sumi, "Sumi", "bg-[#e84a1c]"}],
      fn {theme, _label, _swatch} -> theme in themes end
    )
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  defp translate_error({msg, opts}) when is_binary(msg) do
    Enum.reduce(opts, msg, fn {k, v}, acc ->
      # Handle tuple values gracefully instead of crashing
      value_string =
        case v do
          {_, _} = tuple -> inspect(tuple)
          other -> to_string(other)
        end

      String.replace(acc, "%{#{k}}", value_string)
    end)
  end

  @doc """
  Renders a loading spinner.

  ## Examples

      <.spinner />
      <.spinner size="32" />
      <.spinner class="text-blue-500" />
  """
  attr(:size, :string, default: "24")
  attr(:class, :string, default: "")
  attr(:rest, :global)

  def spinner(assigns) do
    ~H"""
    <svg 
      class={["text-gray-300 dark:text-gray-600 animate-spin", @class]}
      viewBox="0 0 64 64" 
      fill="none" 
      xmlns="http://www.w3.org/2000/svg"
      width={@size}
      height={@size}
      {@rest}
    >
      <path
        d="M32 3C35.8083 3 39.5794 3.75011 43.0978 5.20749C46.6163 6.66488 49.8132 8.80101 52.5061 11.4939C55.199 14.1868 57.3351 17.3837 58.7925 20.9022C60.2499 24.4206 61 28.1917 61 32C61 35.8083 60.2499 39.5794 58.7925 43.0978C57.3351 46.6163 55.199 49.8132 52.5061 52.5061C49.8132 55.199 46.6163 57.3351 43.0978 58.7925C39.5794 60.2499 35.8083 61 32 61C28.1917 61 24.4206 60.2499 20.9022 58.7925C17.3837 57.3351 14.1868 55.199 11.4939 52.5061C8.801 49.8132 6.66487 46.6163 5.20749 43.0978C3.7501 39.5794 3 35.8083 3 32C3 28.1917 3.75011 24.4206 5.2075 20.9022C6.66489 17.3837 8.80101 14.1868 11.4939 11.4939C14.1868 8.80099 17.3838 6.66487 20.9022 5.20749C24.4206 3.7501 28.1917 3 32 3L32 3Z"
        stroke="currentColor" 
        stroke-width="5" 
        stroke-linecap="round" 
        stroke-linejoin="round"
      />
      <path
        d="M32 3C36.5778 3 41.0906 4.08374 45.1692 6.16256C49.2477 8.24138 52.7762 11.2562 55.466 14.9605C58.1558 18.6647 59.9304 22.9531 60.6448 27.4748C61.3591 31.9965 60.9928 36.6232 59.5759 40.9762"
        stroke="currentColor" 
        stroke-width="5" 
        stroke-linecap="round" 
        stroke-linejoin="round" 
        class="text-pink-600 dark:text-pink-500"
      />
    </svg>
    """
  end
end
