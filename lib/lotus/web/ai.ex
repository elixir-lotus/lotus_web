defmodule Lotus.Web.AI do
  @moduledoc false

  # Whether the dashboard shows AI, asked on every render: whether AI is on
  # may change while the node runs (a setting), whether its dependency
  # (`req_llm`, optional to Lotus) is loaded does not.

  @doc "Whether AI is on and can run: its controls show."
  def enabled?, do: Lotus.AI.enabled?()

  @doc "Whether AI is switched on in the config, but its dependency is not installed."
  def missing_dependency?, do: Lotus.Config.ai_enabled?() and not Lotus.AI.available?()

  @doc """
  Whether the assistant's button shows: when AI can run, and when it is
  configured but cannot, so that the panel says why.
  """
  def assistant?, do: missing_dependency?() or enabled?()
end
