defmodule Lotus.Web.Pro do
  @moduledoc false

  # The module, a setting only so that tests can stand in for it.
  defp pro_web, do: Application.get_env(:lotus_web, :__pro_web__, Lotus.Pro.Web)

  @doc """
  Returns `true` if `Lotus.Pro.Web` is available at runtime.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(pro_web())
  end

  @doc """
  Returns Pro page descriptors, or `[]` if Pro is not installed.
  """
  @spec extra_pages() :: [map()]
  def extra_pages do
    if available?(), do: apply(pro_web(), :pages, []), else: []
  end

  @doc """
  Returns Pro nav item descriptors for the given assigns, or `[]` if Pro is not installed.
  """
  @spec nav_items(map()) :: [map()]
  def nav_items(assigns) do
    if available?(), do: apply(pro_web(), :nav_items, [assigns]), else: []
  end

  @doc """
  Renders Pro slot content, or `nil` if Pro is not installed.
  """
  @spec render_slot(atom(), map()) :: term() | nil
  def render_slot(name, assigns) do
    if available?(), do: apply(pro_web(), :render_slot, [name, assigns]), else: nil
  end

  @doc """
  Lets Pro watch a dashboard that a LiveView shows, for live updates: Pro
  sends the LiveView `{:card_result, card_id, result}` when a card's data
  changes, as a card that ran does. Does nothing without Pro.
  """
  @spec watch_dashboard(map(), pid()) :: :ok
  def watch_dashboard(dashboard, pid) do
    if available?() and function_exported?(pro_web(), :watch_dashboard, 2),
      do: apply(pro_web(), :watch_dashboard, [dashboard, pid])

    :ok
  end

  @doc """
  Whether a public dashboard may be shown through its share link, asked on
  every load of the link with the URL's params: `:allow`, or
  `{:deny, message}` to show the message instead of the dashboard. Without
  Pro, or when Pro does not decide, every link is allowed, as before. An
  answer it does not understand denies.
  """
  @spec authorize_public_dashboard(map(), map()) :: :allow | {:deny, String.t() | nil}
  def authorize_public_dashboard(dashboard, params) do
    if available?() and function_exported?(pro_web(), :authorize_public_dashboard, 2) do
      case apply(pro_web(), :authorize_public_dashboard, [dashboard, params]) do
        :allow -> :allow
        {:deny, message} when is_binary(message) -> {:deny, message}
        _other -> {:deny, nil}
      end
    else
      :allow
    end
  end

  @doc """
  The branding of a request, asked when the dashboard mounts and when a
  public dashboard is loaded. `info` has the `:user`, `:context` and
  `:scope` of the request, `:public` and, on a public dashboard, the
  `:dashboard`. Pro answers a map with any of `:product_name`, `:logo` (an
  image URL), `:assistant_name`, `:theme` and `:theme_colors`. The
  "Powered by Lotus" footer is not part of it: it always shows. `%{}` without Pro: the dashboard
  is Lotus.
  """
  @spec branding(map()) :: map()
  def branding(info) do
    with true <- available?() and function_exported?(pro_web(), :branding, 1),
         %{} = branding <- apply(pro_web(), :branding, [info]) do
      branding
    else
      _ -> %{}
    end
  end
end
