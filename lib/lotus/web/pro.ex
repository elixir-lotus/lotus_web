defmodule Lotus.Web.Pro do
  @moduledoc false

  @pro_web Lotus.Pro.Web

  @doc """
  Returns `true` if `Lotus.Pro.Web` is available at runtime.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(@pro_web)
  end

  @doc """
  Returns Pro page descriptors, or `[]` if Pro is not installed.
  """
  @spec extra_pages() :: [map()]
  def extra_pages do
    if available?(), do: apply(@pro_web, :pages, []), else: []
  end

  @doc """
  Returns Pro nav item descriptors for the given assigns, or `[]` if Pro is not installed.
  """
  @spec nav_items(map()) :: [map()]
  def nav_items(assigns) do
    if available?(), do: apply(@pro_web, :nav_items, [assigns]), else: []
  end

  @doc """
  Renders Pro slot content, or `nil` if Pro is not installed.
  """
  @spec render_slot(atom(), map()) :: term() | nil
  def render_slot(name, assigns) do
    if available?(), do: apply(@pro_web, :render_slot, [name, assigns]), else: nil
  end

  @doc """
  Lets Pro watch a dashboard that a LiveView shows, for live updates: Pro
  sends the LiveView `{:card_result, card_id, result}` when a card's data
  changes, as a card that ran does. Does nothing without Pro.
  """
  @spec watch_dashboard(map(), pid()) :: :ok
  def watch_dashboard(dashboard, pid) do
    if available?() and function_exported?(@pro_web, :watch_dashboard, 2),
      do: apply(@pro_web, :watch_dashboard, [dashboard, pid])

    :ok
  end
end
