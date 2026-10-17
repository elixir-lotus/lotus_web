defmodule Lotus.Web.Dashboards.DateTokens do
  @moduledoc """
  The relative date tokens a dashboard filter offers, with their labels.

  The tokens and the dates they cover come from `Lotus.Dashboards.DateToken`.
  This module gives each token a translated label, puts the tokens in groups,
  and gives them as the presets of a `Koyomi` picker, whose keys are the
  tokens.
  """

  use Gettext, backend: Lotus.Web.Gettext

  alias Lotus.Dashboards.DateToken

  @day_tokens ~w(today yesterday last_7_days last_30_days last_90_days)
  @this_tokens ~w(this_week this_month this_quarter this_year)
  @last_tokens ~w(last_week last_month last_quarter last_year)

  @doc """
  Returns the tokens a filter of `filter_type` accepts, in groups for a picker.

  A `:date_range` filter accepts every token. A `:date` filter accepts only
  the tokens for one day, as `Lotus.Storage.DashboardFilter` requires. Other
  filter types accept no token.
  """
  @spec groups(atom()) :: [[String.t()]]
  def groups(:date_range), do: [@day_tokens, @this_tokens, @last_tokens]
  def groups(:date), do: [Enum.filter(DateToken.tokens(), &DateToken.single_day?/1)]
  def groups(_filter_type), do: []

  @doc """
  Returns the tokens a filter of `filter_type` accepts, in picker order.
  """
  @spec tokens(atom()) :: [String.t()]
  def tokens(filter_type), do: filter_type |> groups() |> List.flatten()

  @doc """
  Returns the tokens a filter of `filter_type` accepts as the presets of a
  `Koyomi` picker, in picker order. Each preset's key is its token, so a
  relative picker posts the token.
  """
  @spec presets(atom()) :: [Koyomi.Presets.preset()]
  def presets(filter_type) do
    for token <- tokens(filter_type), {:ok, preset} <- [Koyomi.Presets.parse(token)], do: preset
  end

  @doc """
  Returns `true` when `value` is a relative date token.
  """
  @spec token?(term()) :: boolean()
  def token?(value), do: value in DateToken.tokens()

  @doc """
  Returns the translated label of `token`.
  """
  @spec label(String.t()) :: String.t()
  def label("today"), do: gettext("Today")
  def label("yesterday"), do: gettext("Yesterday")
  def label("last_7_days"), do: gettext("Last 7 days")
  def label("last_30_days"), do: gettext("Last 30 days")
  def label("last_90_days"), do: gettext("Last 90 days")
  def label("this_week"), do: gettext("This week")
  def label("this_month"), do: gettext("This month")
  def label("this_quarter"), do: gettext("This quarter")
  def label("this_year"), do: gettext("This year")
  def label("last_week"), do: gettext("Last week")
  def label("last_month"), do: gettext("Last month")
  def label("last_quarter"), do: gettext("Last quarter")
  def label("last_year"), do: gettext("Last year")
  def label(value), do: to_string(value)
end
