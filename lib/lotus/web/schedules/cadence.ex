defmodule Lotus.Web.Schedules.Cadence do
  @moduledoc false

  # How often a schedule runs, as the picker of the schedule editor shows it,
  # and the cron expression Lotus stores for it.
  #
  # A cadence is a map of strings, as a form posts it:
  #
  #   * `"frequency"`: `"minutes"`, `"hourly"`, `"daily"`, `"weekly"`,
  #     `"monthly"` or `"custom"`;
  #   * `"every"`: the minutes (`"minutes"`) or hours (`"hourly"`) between runs;
  #   * `"minute"`: the minute past the hour of an hourly run;
  #   * `"time"`: the time of day, `"08:00"`;
  #   * `"weekdays"`: `"true"` for a daily run on Monday to Friday only;
  #   * `"days"`: the ISO weekdays of a weekly run, `["1", "3"]`;
  #   * `"month_mode"`: `"day"` (on `"month_day"`), `"last"` (the last day)
  #     or `"weekday"` (on the `"ordinal"` `"weekday"`, such as the last
  #     Friday);
  #   * `"cron"`: the expression of a custom cadence.
  #
  # `from_cron/1` reads any expression: one the picker can show becomes its
  # cadence, any other a custom one.

  use Gettext, backend: Lotus.Web.Gettext

  alias Lotus.Schedules.Cron

  @minute_steps ~w(5 10 15 30)
  @hour_steps ~w(1 2 3 4 6 8 12)

  @doc false
  def minute_steps, do: @minute_steps

  @doc false
  def hour_steps, do: @hour_steps

  @doc "The cadence of a new schedule: Mondays at 08:00."
  def default do
    %{
      "frequency" => "weekly",
      "every" => "15",
      "minute" => "0",
      "time" => "08:00",
      "weekdays" => "false",
      "days" => ["1"],
      "month_mode" => "day",
      "month_day" => "1",
      "ordinal" => "1",
      "weekday" => "1",
      "cron" => "0 8 * * 1"
    }
  end

  @doc "Merges a form's params into a cadence."
  def merge(cadence, params) when is_map(params) do
    cadence = Map.merge(cadence, Map.take(params, Map.keys(default())))

    # Unchecking every weekday posts none: the hidden "" keeps the key.
    days = cadence["days"] |> List.wrap() |> Enum.reject(&(&1 == ""))
    %{cadence | "days" => days}
  end

  ## Cron

  @doc "The cron expression of a cadence."
  def to_cron(%{"frequency" => "custom"} = cadence), do: String.trim(cadence["cron"] || "")

  def to_cron(%{"frequency" => "minutes"} = cadence),
    do: "*/#{pick(cadence["every"], @minute_steps)} * * * *"

  def to_cron(%{"frequency" => "hourly"} = cadence) do
    minute = number(cadence["minute"], 0..59, 0)

    case pick(cadence["every"], @hour_steps) do
      "1" -> "#{minute} * * * *"
      hours -> "#{minute} */#{hours} * * *"
    end
  end

  def to_cron(%{"frequency" => "daily"} = cadence) do
    {hour, minute} = time(cadence["time"])
    days = if cadence["weekdays"] == "true", do: "1-5", else: "*"
    "#{minute} #{hour} * * #{days}"
  end

  def to_cron(%{"frequency" => "weekly"} = cadence) do
    {hour, minute} = time(cadence["time"])

    days =
      cadence["days"]
      |> List.wrap()
      |> Enum.map(&number(&1, 1..7, nil))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    case days do
      [] -> "#{minute} #{hour} * * 1"
      days -> "#{minute} #{hour} * * #{Enum.map_join(days, ",", &cron_day/1)}"
    end
  end

  def to_cron(%{"frequency" => "monthly"} = cadence) do
    {hour, minute} = time(cadence["time"])

    case cadence["month_mode"] do
      "last" ->
        "#{minute} #{hour} L * *"

      "weekday" ->
        day = cron_day(number(cadence["weekday"], 1..7, 1))

        case cadence["ordinal"] do
          "last" -> "#{minute} #{hour} * * #{day}L"
          ordinal -> "#{minute} #{hour} * * #{day}##{number(ordinal, 1..4, 1)}"
        end

      _day ->
        "#{minute} #{hour} #{number(cadence["month_day"], 1..31, 1)} * *"
    end
  end

  def to_cron(cadence), do: to_cron(Map.put(cadence, "frequency", "weekly"))

  @doc "The cadence of a cron expression: a preset's when the picker can show it."
  def from_cron(cron) when is_binary(cron) do
    fields = String.split(cron)
    preset(fields) || Map.merge(default(), %{"frequency" => "custom", "cron" => cron})
  end

  def from_cron(_cron), do: default()

  defp preset([minute, hour, day, "*", weekday]) do
    case read(minute, hour, day, weekday) do
      {:ok, cadence} ->
        cadence = Map.merge(default(), cadence)
        Map.put(cadence, "cron", to_cron(cadence))

      :error ->
        nil
    end
  end

  defp preset(_fields), do: nil

  defp read("*/" <> every, "*", "*", "*") when every in @minute_steps,
    do: {:ok, %{"frequency" => "minutes", "every" => every}}

  defp read(minute, "*", "*", "*"), do: hourly(minute, "1")

  defp read(minute, "*/" <> every, "*", "*") when every in @hour_steps,
    do: hourly(minute, every)

  defp read(minute, hour, day, weekday) do
    with {:ok, time} <- read_time(minute, hour), do: read_day(time, day, weekday)
  end

  defp hourly(minute, every) do
    with {:ok, minute} <- integer(minute, 0..59),
         do: {:ok, %{"frequency" => "hourly", "every" => every, "minute" => to_string(minute)}}
  end

  defp read_day(time, "*", "*"), do: {:ok, %{"frequency" => "daily", "time" => time}}

  defp read_day(time, "L", "*"),
    do: {:ok, %{"frequency" => "monthly", "month_mode" => "last", "time" => time}}

  defp read_day(time, day, "*") do
    with {:ok, day} <- integer(day, 1..31) do
      {:ok,
       %{
         "frequency" => "monthly",
         "month_mode" => "day",
         "month_day" => to_string(day),
         "time" => time
       }}
    end
  end

  defp read_day(time, "*", weekday), do: read_weekday(time, weekday)
  defp read_day(_time, _day, _weekday), do: :error

  defp read_weekday(time, weekday) when weekday in ~w(1-5 MON-FRI),
    do: {:ok, %{"frequency" => "daily", "weekdays" => "true", "time" => time}}

  defp read_weekday(time, weekday) do
    cond do
      String.ends_with?(weekday, "L") ->
        nth_weekday(time, [String.trim_trailing(weekday, "L"), "last"])

      String.contains?(weekday, "#") ->
        nth_weekday(time, String.split(weekday, "#"))

      true ->
        with {:ok, days} <- weekdays(weekday), do: weekly(time, days)
    end
  end

  # The last Friday (`5L`) or the second Monday (`1#2`) of the month.
  defp nth_weekday(time, [day, ordinal]) when ordinal in ~w(1 2 3 4 last) do
    with {:ok, day} <- weekday_number(day), do: {:ok, monthly_weekday(time, day, ordinal)}
  end

  defp nth_weekday(_time, _parts), do: :error

  defp weekly(time, days) do
    if days == Enum.to_list(1..7),
      do: {:ok, %{"frequency" => "daily", "time" => time}},
      else:
        {:ok, %{"frequency" => "weekly", "days" => Enum.map(days, &to_string/1), "time" => time}}
  end

  defp monthly_weekday(time, day, ordinal) do
    %{
      "frequency" => "monthly",
      "month_mode" => "weekday",
      "weekday" => to_string(day),
      "ordinal" => ordinal,
      "time" => time
    }
  end

  defp read_time(minute, hour) do
    with {:ok, minute} <- integer(minute, 0..59),
         {:ok, hour} <- integer(hour, 0..23),
         do: {:ok, clock(hour, minute)}
  end

  # "1,3,5", "MON,WED", "MON-WED": ISO weekdays, sorted.
  defp weekdays(text) do
    parts = text |> String.split(",") |> Enum.map(&weekday_part/1)

    if Enum.member?(parts, :error),
      do: :error,
      else: {:ok, parts |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()}
  end

  defp weekday_part(part) do
    case String.split(part, "-") do
      [day] -> with {:ok, day} <- weekday_number(day), do: {:ok, [day]}
      [first, last] -> weekday_range(first, last)
      _parts -> :error
    end
  end

  # A range counts as cron does, Sunday first: 0-6, SUN-SAT.
  defp weekday_range(first, last) do
    with {:ok, first} <- cron_number(first),
         {:ok, last} <- cron_number(last),
         true <- first <= last do
      {:ok, Enum.map(first..last, &if(&1 == 0, do: 7, else: &1))}
    else
      _ -> :error
    end
  end

  @names ~w(MON TUE WED THU FRI SAT SUN)

  defp weekday_number(day) do
    case Enum.find_index(@names, &(&1 == String.upcase(day))) do
      nil ->
        case integer(day, 0..7) do
          {:ok, 0} -> {:ok, 7}
          {:ok, day} -> {:ok, day}
          :error -> :error
        end

      index ->
        {:ok, index + 1}
    end
  end

  defp cron_number(day) do
    case weekday_number(day) do
      {:ok, 7} -> if day in ["7"], do: {:ok, 7}, else: {:ok, 0}
      other -> other
    end
  end

  # ISO 7 (Sunday) is cron's 0.
  defp cron_day(7), do: 0
  defp cron_day(day), do: day

  ## Sentences

  @doc """
  The cadence in a sentence: "Every Monday at 08:00". A custom expression the
  picker cannot show is "On a custom schedule".
  """
  def describe(cron) when is_binary(cron), do: cron |> from_cron() |> sentence()
  def describe(_cron), do: gettext("On a custom schedule")

  @doc "A cadence's sentence."
  def sentence(%{"frequency" => "minutes", "every" => every}) do
    count = String.to_integer(pick(every, @minute_steps))
    ngettext("Every minute", "Every %{count} minutes", count)
  end

  def sentence(%{"frequency" => "hourly"} = cadence) do
    count = String.to_integer(pick(cadence["every"], @hour_steps))
    minute = minute_label(number(cadence["minute"], 0..59, 0))

    ngettext("Every hour at %{minute}", "Every %{count} hours at %{minute}", count,
      minute: minute
    )
  end

  def sentence(%{"frequency" => "daily"} = cadence) do
    if cadence["weekdays"] == "true",
      do: gettext("Every weekday at %{time}", time: time_label(cadence["time"])),
      else: gettext("Every day at %{time}", time: time_label(cadence["time"]))
  end

  def sentence(%{"frequency" => "weekly"} = cadence) do
    days =
      cadence["days"]
      |> List.wrap()
      |> Enum.map(&number(&1, 1..7, nil))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    case days do
      [1, 2, 3, 4, 5] ->
        sentence(%{cadence | "frequency" => "daily", "weekdays" => "true"})

      [1, 2, 3, 4, 5, 6, 7] ->
        sentence(%{cadence | "frequency" => "daily", "weekdays" => "false"})

      days ->
        gettext("Every %{days} at %{time}",
          days: days |> Enum.map(&day_name/1) |> join(),
          time: time_label(cadence["time"])
        )
    end
  end

  def sentence(%{"frequency" => "monthly"} = cadence) do
    time = time_label(cadence["time"])

    case cadence["month_mode"] do
      "last" ->
        gettext("Every month on the last day at %{time}", time: time)

      "weekday" ->
        gettext("Every month on the %{ordinal} %{weekday} at %{time}",
          ordinal: ordinal_name(cadence["ordinal"]),
          weekday: day_name(number(cadence["weekday"], 1..7, 1)),
          time: time
        )

      _day ->
        gettext("Every month on day %{day} at %{time}",
          day: number(cadence["month_day"], 1..31, 1),
          time: time
        )
    end
  end

  # A custom expression that a preset can say is said as that preset.
  def sentence(%{"frequency" => "custom", "cron" => cron}) when is_binary(cron) do
    case from_cron(cron) do
      %{"frequency" => "custom"} -> gettext("On a custom schedule")
      cadence -> sentence(cadence)
    end
  end

  def sentence(_cadence), do: gettext("On a custom schedule")

  @doc "The name of an ISO weekday."
  def day_name(1), do: gettext("Monday")
  def day_name(2), do: gettext("Tuesday")
  def day_name(3), do: gettext("Wednesday")
  def day_name(4), do: gettext("Thursday")
  def day_name(5), do: gettext("Friday")
  def day_name(6), do: gettext("Saturday")
  def day_name(7), do: gettext("Sunday")

  @doc "The short name of an ISO weekday, for the weekday buttons."
  def day_initial(1), do: gettext("Mon")
  def day_initial(2), do: gettext("Tue")
  def day_initial(3), do: gettext("Wed")
  def day_initial(4), do: gettext("Thu")
  def day_initial(5), do: gettext("Fri")
  def day_initial(6), do: gettext("Sat")
  def day_initial(7), do: gettext("Sun")

  @doc "The word of an ordinal: first to fourth, or last."
  def ordinal_name("last"), do: gettext("last")
  def ordinal_name("2"), do: gettext("second")
  def ordinal_name("3"), do: gettext("third")
  def ordinal_name("4"), do: gettext("fourth")
  def ordinal_name(_first), do: gettext("first")

  defp join([one]), do: one

  defp join(names) do
    {init, [last]} = Enum.split(names, -1)
    gettext("%{list} and %{last}", list: Enum.join(init, ", "), last: last)
  end

  defp minute_label(0), do: gettext("o'clock")
  defp minute_label(minute), do: gettext("%{minute} past", minute: minute)

  defp time_label(text) do
    {hour, minute} = time(text)
    clock(hour, minute)
  end

  ## Next runs

  @doc """
  The next `count` runs of `cron` in `time_zone` after `from`, as UTC
  `DateTime`s; none for an expression or a zone that is not valid.
  """
  def next_runs(cron, time_zone, count, from \\ DateTime.utc_now()) do
    Enum.reduce_while(1..count, {from, []}, fn _n, {from, runs} ->
      case Cron.next_run(cron, time_zone, from) do
        {:ok, at} -> {:cont, {at, [at | runs]}}
        _error -> {:halt, {from, runs}}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  rescue
    _error -> []
  end

  @doc "Whether `cron` is an expression Lotus runs: `:ok` or `{:error, message}`."
  def validate(cron) do
    case Cron.parse(cron || "") do
      {:ok, _parsed} -> :ok
      {:error, message} -> {:error, message}
    end
  end

  ## Helpers

  defp pick(value, allowed) when is_binary(value),
    do: if(value in allowed, do: value, else: hd(allowed))

  defp pick(_value, allowed), do: hd(allowed)

  defp number(value, range, default) when is_binary(value) do
    case integer(value, range) do
      {:ok, n} -> n
      :error -> default
    end
  end

  defp number(value, range, default) when is_integer(value),
    do: if(value in range, do: value, else: default)

  defp number(_value, _range, default), do: default

  defp integer(text, range) do
    case Integer.parse(text) do
      {n, ""} -> if n in range, do: {:ok, n}, else: :error
      _ -> :error
    end
  end

  # "08:00" or Koyomi's "08:00:00": {8, 0}.
  @doc false
  def time(text) when is_binary(text) do
    case String.split(text, ":") do
      [hour, minute | _seconds] ->
        {number(hour, 0..23, 8), number(minute, 0..59, 0)}

      _ ->
        {8, 0}
    end
  end

  def time(_text), do: {8, 0}

  defp clock(hour, minute),
    do: String.pad_leading("#{hour}", 2, "0") <> ":" <> String.pad_leading("#{minute}", 2, "0")
end
