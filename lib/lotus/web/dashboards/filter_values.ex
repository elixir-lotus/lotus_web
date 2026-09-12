defmodule Lotus.Web.Dashboards.FilterValues do
  @moduledoc """
  Canonical form for the filter values a dashboard carries.

  A filter value is a string. That is what survives a round-trip through the
  URL query string, and it is what `Lotus.Dashboards` expects when it applies
  a filter's transform to a card's query variables.

  The one filter that does not arrive as a string is the date range. Its
  picker is two `<input type="date">` elements posted under one filter name,
  so Phoenix parses them into `%{"start" => _, "end" => _}`. `normalize/1`
  flattens that to `"start,end"`, which is the shape the
  `date_range_start` and `date_range_end` transforms already parse.
  """

  @doc """
  Reduces posted filter params to their canonical string form.
  """
  @spec normalize(map()) :: %{optional(String.t()) => String.t()}
  def normalize(filter_values) when is_map(filter_values) do
    Map.new(filter_values, fn {name, value} -> {name, normalize_value(value)} end)
  end

  def normalize(_filter_values), do: %{}

  @doc """
  Builds the filter values for a dashboard from URL params, falling back to
  each filter's default.
  """
  @spec from_params(map(), [struct()]) :: %{optional(String.t()) => String.t()}
  def from_params(params, filters) do
    params = normalize(params)

    for filter <- filters,
        value = present(Map.get(params, filter.name)) || present(filter.default_value),
        into: %{},
        do: {filter.name, value}
  end

  @doc """
  Reduces filter values to the params worth putting in the URL, dropping the
  ones carrying nothing.
  """
  @spec to_params(map()) :: map()
  def to_params(filter_values) do
    filter_values
    |> normalize()
    |> Enum.reject(fn {_name, value} -> value in ["", nil] end)
    |> Map.new()
  end

  @doc """
  Splits a canonical date-range value into its two dates, either of which may
  be `nil` when that end of the range is open.
  """
  @spec split_date_range(term()) :: {String.t() | nil, String.t() | nil}
  def split_date_range(value) when is_binary(value) do
    case String.split(value, ",", parts: 2) do
      [start_value, end_value] -> {present(start_value), present(end_value)}
      [single] -> {present(single), nil}
    end
  end

  # A value that never made it through normalize/1, from an older saved URL
  # or a caller building values by hand.
  def split_date_range(%{"start" => start_value, "end" => end_value}),
    do: {present(start_value), present(end_value)}

  def split_date_range(%{start: start_value, end: end_value}),
    do: {present(start_value), present(end_value)}

  def split_date_range(_value), do: {nil, nil}

  defp normalize_value(%{"start" => start_value, "end" => end_value}),
    do: join_date_range(start_value, end_value)

  defp normalize_value(%{start: start_value, end: end_value}),
    do: join_date_range(start_value, end_value)

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(nil), do: ""
  defp normalize_value(value), do: to_string(value)

  # An open end keeps its comma, so "2026-01-01," still reads as a start with
  # no end rather than collapsing into a bare date.
  defp join_date_range(start_value, end_value) do
    case {blank_to_empty(start_value), blank_to_empty(end_value)} do
      {"", ""} -> ""
      {start_value, end_value} -> start_value <> "," <> end_value
    end
  end

  defp blank_to_empty(nil), do: ""
  defp blank_to_empty(value) when is_binary(value), do: value
  defp blank_to_empty(value), do: to_string(value)

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil
end
