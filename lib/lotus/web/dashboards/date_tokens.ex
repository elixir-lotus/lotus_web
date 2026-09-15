defmodule Lotus.Web.Dashboards.DateTokens do
  @moduledoc """
  The relative date tokens a dashboard filter offers, with their labels.

  The tokens and the dates they cover come from `Lotus.Dashboards.DateToken`.
  This module gives each token a translated label, puts the tokens in groups
  for a picker, and formats the dates a token covers on a given day.
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

  @doc """
  Returns the concrete value `token` resolves to on `today` for a filter of
  `filter_type`: `"YYYY-MM-DD,YYYY-MM-DD"` for a range, `"YYYY-MM-DD"` for a
  day.
  """
  @spec resolve(String.t(), atom(), Date.t()) :: String.t()
  def resolve(token, filter_type, today), do: DateToken.resolve(token, filter_type, today)

  @doc """
  Formats the dates `token` covers on `today`, for example
  `"Aug 17 – Sep 15, 2026"`. Returns `nil` when `token` is not a token.
  """
  @spec describe(term(), Date.t()) :: String.t() | nil
  def describe(token, today) do
    case DateToken.range(token, today) do
      {:ok, range} -> format_range(range.first, range.last)
      :error -> nil
    end
  end

  @doc """
  Formats a date range for a person to read. A range in one year shows the
  year once, and a range of one day shows one date.
  """
  @spec format_range(Date.t(), Date.t()) :: String.t()
  def format_range(first, first), do: format_date(first)

  def format_range(%Date{year: year} = first, %Date{year: year} = last),
    do: strftime(first, gettext("%b %-d")) <> " – " <> format_date(last)

  def format_range(first, last), do: format_date(first) <> " – " <> format_date(last)

  @doc """
  Formats a date for a person to read, for example `"Sep 15, 2026"`.
  """
  @spec format_date(Date.t()) :: String.t()
  def format_date(date), do: strftime(date, gettext("%b %-d, %Y"))

  defp strftime(date, format),
    do: Calendar.strftime(date, format, abbreviated_month_names: &month_abbreviation/1)

  defp month_abbreviation(1), do: pgettext("abbreviated month", "Jan")
  defp month_abbreviation(2), do: pgettext("abbreviated month", "Feb")
  defp month_abbreviation(3), do: pgettext("abbreviated month", "Mar")
  defp month_abbreviation(4), do: pgettext("abbreviated month", "Apr")
  defp month_abbreviation(5), do: pgettext("abbreviated month", "May")
  defp month_abbreviation(6), do: pgettext("abbreviated month", "Jun")
  defp month_abbreviation(7), do: pgettext("abbreviated month", "Jul")
  defp month_abbreviation(8), do: pgettext("abbreviated month", "Aug")
  defp month_abbreviation(9), do: pgettext("abbreviated month", "Sep")
  defp month_abbreviation(10), do: pgettext("abbreviated month", "Oct")
  defp month_abbreviation(11), do: pgettext("abbreviated month", "Nov")
  defp month_abbreviation(12), do: pgettext("abbreviated month", "Dec")
end
