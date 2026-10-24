defmodule Lotus.Web.Schedules.TimeZones do
  @moduledoc false

  # The time zones the schedule editor offers, each with its city, its region,
  # its offset from UTC and the time there now. Any other IANA name that the
  # time zone database knows can be typed in the search.

  alias Lotus.Schedules.Cron

  @zones ~w(
    Etc/UTC
    Pacific/Midway Pacific/Honolulu America/Anchorage America/Los_Angeles America/Vancouver
    America/Tijuana America/Phoenix America/Denver America/Edmonton America/Chicago
    America/Mexico_City America/Winnipeg America/New_York America/Toronto America/Bogota
    America/Lima America/Caracas America/Halifax America/Santiago America/St_Johns
    America/Sao_Paulo America/Argentina/Buenos_Aires America/Montevideo Atlantic/Azores
    Atlantic/Cape_Verde Atlantic/Reykjavik Europe/London Europe/Dublin Europe/Lisbon
    Africa/Casablanca Africa/Lagos Europe/Madrid Europe/Paris Europe/Brussels
    Europe/Amsterdam Europe/Berlin Europe/Zurich Europe/Rome Europe/Vienna Europe/Prague
    Europe/Stockholm Europe/Oslo Europe/Copenhagen Europe/Warsaw Europe/Budapest
    Europe/Athens Europe/Bucharest Europe/Helsinki Europe/Kyiv Europe/Istanbul
    Africa/Cairo Africa/Johannesburg Africa/Nairobi Asia/Jerusalem Asia/Beirut
    Europe/Moscow Asia/Riyadh Asia/Baghdad Asia/Tehran Asia/Dubai Asia/Baku Asia/Kabul
    Asia/Karachi Asia/Tashkent Asia/Kolkata Asia/Colombo Asia/Kathmandu Asia/Dhaka
    Asia/Yangon Asia/Bangkok Asia/Jakarta Asia/Ho_Chi_Minh Asia/Shanghai Asia/Hong_Kong
    Asia/Taipei Asia/Singapore Asia/Kuala_Lumpur Asia/Manila Australia/Perth Asia/Seoul
    Asia/Tokyo Australia/Darwin Australia/Adelaide Australia/Brisbane Australia/Sydney
    Australia/Melbourne Pacific/Guam Pacific/Noumea Pacific/Auckland Pacific/Fiji
    Pacific/Tongatapu
  )

  @doc "The zones offered, sorted by their offset now and their city."
  def all(now \\ DateTime.utc_now()) do
    @zones
    |> Enum.map(&entry(&1, now))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.offset, &1.city})
  end

  @doc """
  The zones whose name, city or region has every word of `search`, and the
  zone named exactly `search` when the database knows it and the list does
  not have it.
  """
  def search(search, now \\ DateTime.utc_now()) do
    words = search |> String.downcase() |> String.split(~r/[\s\/_]+/, trim: true)
    zones = all(now)

    found =
      Enum.filter(zones, fn zone ->
        text = String.downcase("#{zone.name} #{zone.city} #{zone.region} #{zone.offset_label}")
        Enum.all?(words, &String.contains?(text, &1))
      end)

    typed = String.trim(search)

    if typed != "" and not Enum.any?(zones, &(&1.name == typed)) and Cron.valid_time_zone?(typed),
      do: [entry(typed, now) | found],
      else: found
  end

  @doc "The entry of one zone, or `nil` for one the database does not know."
  def entry(name, now \\ DateTime.utc_now()) do
    case DateTime.shift_zone(now, name, Cron.database()) do
      {:ok, local} ->
        offset = local.utc_offset + local.std_offset

        %{
          name: name,
          city: city(name),
          region: region(name),
          offset: offset,
          offset_label: offset_label(offset),
          abbreviation: local.zone_abbr,
          now: Calendar.strftime(local, "%H:%M")
        }

      _error ->
        nil
    end
  end

  defp city("Etc/UTC"), do: "UTC"
  defp city(name), do: name |> String.split("/") |> List.last() |> String.replace("_", " ")

  defp region("Etc/UTC"), do: "Coordinated Universal Time"

  defp region(name) do
    case String.split(name, "/") do
      [region | _rest] -> String.replace(region, "_", " ")
      _ -> ""
    end
  end

  @doc "`+01:00` for an offset of 3600 seconds."
  def offset_label(0), do: "UTC"

  def offset_label(seconds) do
    sign = if seconds < 0, do: "−", else: "+"
    seconds = abs(seconds)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    "UTC" <>
      sign <>
      String.pad_leading("#{hours}", 2, "0") <> ":" <> String.pad_leading("#{minutes}", 2, "0")
  end
end
