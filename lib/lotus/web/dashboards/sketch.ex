defmodule Lotus.Web.Dashboards.Sketch do
  @moduledoc """
  A dashboard's layout as a small picture, for the list of dashboards: its
  cards where they are on the grid of its first tab, each drawn as what it
  shows (bars, a line, a pie, a number, rows, lines of text, a map). Drawn
  from the layout the dashboard keeps, so it is always as the dashboard is.
  """

  use Phoenix.Component

  alias Lotus.Web.Dashboards.Tabs
  alias Lotus.Web.Dashboards.TextCard

  @doc """
  The sketch of a dashboard (with its cards): `:tile` for the gallery,
  `:mini` beside a name in the table.
  """
  attr(:dashboard, :map, required: true)
  attr(:size, :atom, default: :tile, values: [:tile, :mini])
  attr(:class, :any, default: nil)

  def sketch(assigns) do
    {w, h} = if assigns.size == :mini, do: {80, 48}, else: {300, 132}
    small = assigns.size == :mini

    cards =
      assigns.dashboard |> Tabs.cards(Tabs.current(assigns.dashboard, nil)) |> Enum.map(&shape/1)

    assigns =
      assign(assigns,
        w: w,
        h: h,
        small: small,
        marks: marks(cards, w, h, small)
      )

    ~H"""
    <svg
      viewBox={"0 0 #{@w} #{@h}"}
      class={["lotus-sketch block h-full w-full", @small && "lotus-sketch-mini", @class]}
      role="img"
      aria-hidden="true"
    >
      <%= for mark <- @marks do %>
        <%= case mark do %>
          <% {:rect, a} -> %>
            <rect x={a.x} y={a.y} width={a.w} height={a.h} rx={a.r} class={a.class} />
          <% {:path, a} -> %>
            <path d={a.d} class={a.class} />
          <% {:circle, a} -> %>
            <circle cx={a.cx} cy={a.cy} r={a.r} class={a.class} />
        <% end %>
      <% end %>
    </svg>
    """
  end

  # A card as {x, y, w, h, kind}.
  defp shape(card) do
    layout = card.layout || %{}

    get = fn key, default ->
      Map.get(layout, key) || Map.get(layout, to_string(key)) || default
    end

    {get.(:x, 0), get.(:y, 0), get.(:w, 6), get.(:h, 4), kind(card)}
  end

  defp kind(%{card_type: :heading}), do: :heading
  defp kind(%{card_type: :link}), do: :link

  defp kind(%{card_type: :text} = card),
    do: if(TextCard.heading?(card), do: :heading, else: :text)

  defp kind(%{card_type: :query, visualization_config: %{"chart_type" => type}}), do: chart(type)
  defp kind(_card), do: :table

  defp chart(type) when type in ~w(bar horizontal_bar combo histogram waterfall funnel), do: :bar
  defp chart(type) when type in ~w(line sparkline), do: :line
  defp chart("area"), do: :area
  defp chart(type) when type in ~w(pie donut), do: :pie
  defp chart(type) when type in ~w(kpi trend gauge progress), do: :kpi
  defp chart(type) when type in ~w(map bubble_map), do: :map
  defp chart(type) when type in ~w(scatter bubble), do: :dots
  defp chart(_type), do: :table

  defp marks([], _w, _h, _small), do: []

  defp marks(cards, w, h, small) do
    rows = cards |> Enum.map(fn {_x, y, _w, h, _k} -> y + h end) |> Enum.max()
    gap = if small, do: 1.2, else: 3
    pitch_x = w / 12
    pitch_y = min(h / rows, pitch_x * 1.05)
    top = if small, do: 0, else: max(0, (h - rows * pitch_y) / 2)

    Enum.flat_map(cards, fn {x, y, cw, ch, kind} ->
      box = %{
        x: x * pitch_x + gap / 2,
        y: top + y * pitch_y + gap / 2,
        w: max(1, cw * pitch_x - gap),
        h: max(1, ch * pitch_y - gap)
      }

      card(kind, box, small)
    end)
  end

  defp card(:heading, b, _small) do
    [
      rect(
        b.x + 2,
        b.y + b.h * 0.35,
        min(b.w * 0.35, 80),
        max(2, b.h * 0.3),
        1.5,
        "lotus-sketch-heading"
      )
    ]
  end

  defp card(kind, b, small) do
    pad = if small, do: 2.5, else: 7
    inner = %{x: b.x + pad, y: b.y + pad, w: max(1, b.w - 2 * pad), h: max(1, b.h - 2 * pad)}
    frame = rect(b.x, b.y, b.w, b.h, if(small, do: 1.5, else: 4), "lotus-sketch-card")

    {title, body} =
      if small,
        do: {[], inner},
        else:
          {[rect(inner.x, inner.y, min(inner.w * 0.4, 60), 3, 1.5, "lotus-sketch-title")],
           %{inner | y: inner.y + 8, h: max(1, inner.h - 8)}}

    [frame | title] ++ draw(kind, body, small)
  end

  defp draw(:bar, b, small) do
    n = 5
    gap = b.w / n * 0.3
    bw = b.w / n - gap

    [0.9, 0.65, 0.8, 0.45, 0.6]
    |> Enum.with_index()
    |> Enum.map(fn {v, i} ->
      rect(
        b.x + i * (bw + gap) + gap / 2,
        b.y + b.h * (1 - v),
        bw,
        b.h * v,
        if(small, do: 0.5, else: 1.5),
        "lotus-sketch-mark"
      )
    end)
  end

  defp draw(kind, b, _small) when kind in [:line, :area] do
    points =
      [0.6, 0.5, 0.62, 0.4, 0.45, 0.3, 0.35, 0.15]
      |> Enum.with_index()
      |> Enum.map(fn {v, i} -> {b.x + b.w * i / 7, b.y + b.h * v} end)

    d =
      points
      |> Enum.with_index()
      |> Enum.map_join(fn {{x, y}, i} -> "#{if i == 0, do: "M", else: "L"}#{n(x)},#{n(y)}" end)

    line = {:path, %{d: d, class: "lotus-sketch-line"}}

    if kind == :area,
      do: [
        {:path,
         %{
           d: "#{d}L#{n(b.x + b.w)},#{n(b.y + b.h)}L#{n(b.x)},#{n(b.y + b.h)}Z",
           class: "lotus-sketch-fill"
         }},
        line
      ],
      else: [line]
  end

  defp draw(:pie, b, _small) do
    r = min(b.w, b.h) / 2 * 0.9
    {cx, cy} = {b.x + b.w / 2, b.y + b.h / 2}

    [
      {:circle, %{cx: n(cx), cy: n(cy), r: n(r), class: "lotus-sketch-fill"}},
      {:path,
       %{
         d:
           "M#{n(cx)},#{n(cy)}L#{n(cx)},#{n(cy - r)}A#{n(r)},#{n(r)} 0 0 1 #{n(cx + r * 0.95)},#{n(cy + r * 0.3)}Z",
         class: "lotus-sketch-mark"
       }}
    ]
  end

  defp draw(:kpi, b, small) do
    number =
      rect(b.x, b.y + b.h * 0.25, b.w * 0.55, max(2, b.h * 0.32), 1.5, "lotus-sketch-number")

    if small,
      do: [number],
      else: [number, rect(b.x, b.y + b.h * 0.72, b.w * 0.3, 3, 1.5, "lotus-sketch-up")]
  end

  defp draw(:table, b, small) do
    rows = if small, do: 4, else: 6

    for i <- 0..(rows - 1) do
      rect(
        b.x,
        b.y + i * b.h / rows,
        b.w * if(i == 0, do: 1, else: 0.9),
        max(1, b.h / rows * 0.35),
        1,
        if(i == 0, do: "lotus-sketch-heading", else: "lotus-sketch-soft")
      )
    end
  end

  defp draw(:text, b, small) do
    lines = b.h |> div_floor(if small, do: 3, else: 9) |> max(1) |> min(4)

    for i <- 0..(lines - 1) do
      rect(
        b.x,
        b.y + i * b.h / lines,
        b.w * if(i == lines - 1, do: 0.55, else: 0.95),
        max(1, b.h / lines * 0.4),
        1,
        "lotus-sketch-soft"
      )
    end
  end

  defp draw(:link, b, _small),
    do: [rect(b.x, b.y + b.h * 0.35, b.w * 0.5, max(1.5, b.h * 0.25), 1, "lotus-sketch-link")]

  defp draw(:dots, b, small) do
    r = if small, do: 0.9, else: 2.2

    for {fx, fy} <- [
          {0.1, 0.7},
          {0.25, 0.5},
          {0.4, 0.6},
          {0.55, 0.3},
          {0.7, 0.45},
          {0.85, 0.2},
          {0.3, 0.8},
          {0.65, 0.65}
        ] do
      {:circle, %{cx: n(b.x + b.w * fx), cy: n(b.y + b.h * fy), r: r, class: "lotus-sketch-dot"}}
    end
  end

  defp draw(:map, b, _small) do
    [
      {:path,
       %{
         d:
           "M#{n(b.x + b.w * 0.1)},#{n(b.y + b.h * 0.3)}Q#{n(b.x + b.w * 0.25)},#{n(b.y + b.h * 0.1)} #{n(b.x + b.w * 0.4)},#{n(b.y + b.h * 0.3)}" <>
             "T#{n(b.x + b.w * 0.65)},#{n(b.y + b.h * 0.4)}L#{n(b.x + b.w * 0.85)},#{n(b.y + b.h * 0.65)}" <>
             "Q#{n(b.x + b.w * 0.75)},#{n(b.y + b.h)} #{n(b.x + b.w * 0.5)},#{n(b.y + b.h * 0.95)}T#{n(b.x + b.w * 0.2)},#{n(b.y + b.h * 0.7)}Z",
         class: "lotus-sketch-fill"
       }},
      {:path,
       %{
         d:
           "M#{n(b.x + b.w * 0.45)},#{n(b.y + b.h * 0.35)}l#{n(b.w * 0.2)},#{n(b.h * 0.05)}l#{n(b.w * 0.05)},#{n(b.h * 0.25)}l#{n(-b.w * 0.2)},#{n(b.h * 0.1)}z",
         class: "lotus-sketch-mark"
       }}
    ]
  end

  defp rect(x, y, w, h, r, class),
    do: {:rect, %{x: n(x), y: n(y), w: n(max(w, 0.5)), h: n(max(h, 0.5)), r: r, class: class}}

  defp div_floor(a, b), do: trunc(a / b)

  defp n(value) when is_integer(value), do: value
  defp n(value), do: Float.round(value * 1.0, 1)
end
