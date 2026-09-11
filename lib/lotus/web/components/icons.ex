defmodule Lotus.Web.Components.Icons do
  @moduledoc false

  use Lotus.Web, :html

  attr(:rest, :global,
    default: %{
      "aria-hidden": "true",
      class: "w-4 h-4",
      fill: "currentColor",
      viewBox: "0 0 16 16"
    }
  )

  slot(:inner_block, required: true)

  defp svg_mini(assigns) do
    ~H"""
    <svg {@rest}>
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr(:rest, :global,
    default: %{
      "stroke-width": "1.5",
      class: "w-6 h-6",
      fill: "none",
      stroke: "currentColor",
      viewBox: "0 0 24 24"
    }
  )

  slot(:inner_block, required: true)

  defp svg_outline(assigns) do
    ~H"""
    <svg {@rest}>
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr(:rest, :global,
    default: %{
      "aria-hidden": "true",
      class: "w-6 h-6",
      fill: "currentColor",
      viewBox: "0 0 24 24"
    }
  )

  slot(:inner_block, required: true)

  defp svg_solid(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" {@rest}>
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr(:rest, :global)

  def check(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path fill-rule="evenodd" clip-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 1 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def database(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def maximize(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M15 3h6v6"/>
      <path d="m21 3-7 7"/>
      <path d="m3 21 7-7"/>
      <path d="M9 21H3v-6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def minimize(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m14 10 7-7"/>
      <path d="M20 10h-6V4"/>
      <path d="m3 21 7-7"/>
      <path d="M4 14h6v6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def play(assigns) do
    ~H"""
    <.svg_solid {@rest}>
      <path d="M8 5v14l11-7z"/>
    </.svg_solid>
    """
  end

  attr(:rest, :global)

  def play_outline(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def tables(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M9 3H5a2 2 0 0 0-2 2v4m6-6h10a2 2 0 0 1 2 2v4M9 3v18m0 0h10a2 2 0 0 0 2-2V9M9 21H5a2 2 0 0 1-2-2V9m0 0h18"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def table_view(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M9 3v18" />
      <rect width="18" height="18" x="3" y="3" rx="2" />
      <path d="M21 9H3" />
      <path d="M21 15H3" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def terminal(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M12 19h8"/>
      <path d="m4 17 6-6-6-6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def variable(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1"/>
      <path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1"/>
      <g fill="currentColor" transform="translate(12,12) scale(0.45) translate(-12,-12)">
        <path clip-rule="evenodd" d="m9.06548 18.4761c-1.34638 1.6493-3.00206 3.0239-5.06548 3.0239-.55228 0-1-.4477-1-1s.44772-1 1-1c1.12026 0 2.2605-.7504 3.51616-2.2886 1.23641-1.5146 2.39737-3.5576 3.61384-5.7044l.0283-.05c1.1832-2.08816 2.4214-4.2735 3.7762-5.93313 1.3464-1.64931 3.0021-3.02387 5.0655-3.02387.5523 0 1 .44772 1 1 0 .55229-.4477 1-1 1-1.1203 0-2.2605.75044-3.5162 2.28863-1.2364 1.51461-2.3973 3.55757-3.6138 5.70437l-.0283.05c-1.1832 2.0882-2.4214 4.2735-3.77622 5.9331z" fill-rule="evenodd"/>
        <path d="m6.81813 4.53893c-.43622-.03805-.9922-.03893-1.81813-.03893-.55228 0-1-.44771-1-1 0-.55228.44772-1 1-1h.04234c.7728-.00001 1.41629-.00003 1.94962.0465.56129.04897 1.07052.15372 1.56437.40124.50398.2526.95613.60246 1.33717 1.02764.3669.4094.6233.87922.8565 1.42743.2254.53005.4529 1.19311.7332 2.0099l2.9135 8.49089c.295.8596.4997 1.4545.6938 1.9108.1895.4456.343.6942.5054.8754.2203.2458.4733.4388.7439.5745.188.0942.4241.1603.8421.1968.4362.038.9922.0389 1.8181.0389.5523 0 1 .4477 1 1s-.4477 1-1 1h-.0423c-.7728 0-1.4163 0-1.9497-.0465-.5612-.049-1.0705-.1537-1.5643-.4012-.504-.2526-.9562-.6025-1.3372-1.0277-.3669-.4094-.6233-.8792-.8565-1.4274-.2254-.5301-.4529-1.1931-.7332-2.0099l-2.9135-8.49089c-.29497-.85961-.49974-1.45455-.69381-1.91084-.18951-.4456-.34296-.69416-.50538-.87539-.2203-.24581-.47332-.43881-.74394-.57445-.18797-.09421-.42406-.16033-.84204-.1968z"/>
      </g>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def funnel(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M10 20a1 1 0 0 0 .553.895l2 1A1 1 0 0 0 14 21v-7a2 2 0 0 1 .517-1.341L21.74 4.67A1 1 0 0 0 21 3H3a1 1 0 0 0-.742 1.67l7.225 7.989A2 2 0 0 1 10 14z"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def funnel_x(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M12.531 3H3a1 1 0 0 0-.742 1.67l7.225 7.989A2 2 0 0 1 10 14v6a1 1 0 0 0 .553.895l2 1A1 1 0 0 0 14 21v-7a2 2 0 0 1 .517-1.341l.427-.473"/>
      <path stroke-linecap="round" stroke-linejoin="round" d="m16.5 3.5 5 5"/>
      <path stroke-linecap="round" stroke-linejoin="round" d="m21.5 3.5-5 5"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def x_mark(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M18 6 6 18"/><path d="m6 6 12 12"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def layers(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/>
      <path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/>
      <path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def search(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m21 21-4.34-4.34"/>
      <circle cx="11" cy="11" r="8"/>
    </.svg_outline>
    """
  end

  # Column type icons for schema explorer
  attr(:rest, :global)

  def key(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def text_type(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M12 4v16"/>
      <path d="M4 7V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v2"/>
      <path d="M9 20h6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def file_digit(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M4 22h14a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v4"/>
      <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
      <rect width="4" height="6" x="2" y="12" rx="2"/>
      <path d="M10 12h2v6"/>
      <path d="M10 18h4"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def decimals(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M10 18h10"/>
      <path d="m17 21 3-3-3-3"/>
      <path d="M3 11h.01"/>
      <rect x="15" y="3" width="5" height="8" rx="2.5"/>
      <rect x="6" y="3" width="5" height="8" rx="2.5"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def command(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def calendar(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M8 2v4"/>
      <path d="M16 2v4"/>
      <rect width="18" height="18" x="3" y="4" rx="2"/>
      <path d="M3 10h18"/>
      <path d="M8 14h.01"/>
      <path d="M12 14h.01"/>
      <path d="M16 14h.01"/>
      <path d="M8 18h.01"/>
      <path d="M12 18h.01"/>
      <path d="M16 18h.01"/>
    </.svg_outline>
    """
  end

  @doc """
  Renders a clock icon.
  """
  attr(:rest, :global, default: %{class: "w-5 h-5"})

  def clock(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="12" cy="12" r="10"/>
      <polyline points="12 6 12 12 16 14"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def toggle_boolean(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="9" cy="12" r="3"/>
      <rect width="20" height="14" x="2" y="5" rx="7"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def list_bullet(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <line x1="8" y1="6" x2="21" y2="6"/>
      <line x1="8" y1="12" x2="21" y2="12"/>
      <line x1="8" y1="18" x2="21" y2="18"/>
      <line x1="3" y1="6" x2="3.01" y2="6"/>
      <line x1="3" y1="12" x2="3.01" y2="12"/>
      <line x1="3" y1="18" x2="3.01" y2="18"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chevron_left(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m15 18-6-6 6-6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chevron_down(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m6 9 6 6 6-6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chevron_right(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m9 18 6-6-6-6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chevron_up(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m18 15-6-6-6 6"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def sun(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="12" cy="12" r="4"/>
      <path d="M12 2v2"/>
      <path d="M12 20v2"/>
      <path d="m4.93 4.93 1.41 1.41"/>
      <path d="m17.66 17.66 1.41 1.41"/>
      <path d="M2 12h2"/>
      <path d="M20 12h2"/>
      <path d="m6.34 17.66-1.41 1.41"/>
      <path d="m19.07 4.93-1.41 1.41"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def moon(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def monitor(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect width="20" height="14" x="2" y="3" rx="2"/>
      <line x1="8" x2="16" y1="21" y2="21"/>
      <line x1="12" x2="12" y1="17" y2="21"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def download(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M12 15V3"/>
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
      <path d="m7 10 5 5 5-5"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def clipboard_copy(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect width="8" height="4" x="8" y="2" rx="1" ry="1"/>
      <path d="M8 4H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>
      <path d="M16 4h2a2 2 0 0 1 2 2v4"/>
      <path d="M21 14H11"/>
      <path d="m15 10-4 4 4 4"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def information_circle(assigns) do
    ~H"""
    <.svg_solid {@rest}>
      <path d="M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-7-4a1 1 0 1 1-2 0 1 1 0 0 1 2 0ZM9 9a.75.75 0 0 0 0 1.5h.253a.25.25 0 0 1 .244.304l-.459 2.066A1.75 1.75 0 0 0 10.747 15H11a.75.75 0 0 0 0-1.5h-.253a.25.25 0 0 1-.244-.304l.459-2.066A1.75 1.75 0 0 0 9.253 9H9Z" clip-rule="evenodd" fill-rule="evenodd" />
    </.svg_solid>
    """
  end

  attr(:rest, :global)

  def exclamation_triangle(assigns) do
    ~H"""
    <.svg_solid {@rest}>
      <path d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495ZM10 5a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 10 5Zm0 9a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" fill-rule="evenodd" />
    </.svg_solid>
    """
  end

  # Chart icons for visualization

  attr(:rest, :global)

  def chart_bar(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <rect x="15" y="5" width="4" height="12" rx="1" />
      <rect x="7" y="8" width="4" height="9" rx="1" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_bar_big(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <rect x="7" y="13" width="9" height="4" rx="1" />
      <rect x="7" y="5" width="12" height="4" rx="1" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_horizontal_bar(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <rect x="5" y="5" width="12" height="4" rx="1" />
      <rect x="5" y="13" width="8" height="4" rx="1" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_combined(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v5" />
      <path stroke-linecap="round" stroke-linejoin="round" d="M16 14v7" />
      <path stroke-linecap="round" stroke-linejoin="round" d="M20 10v11" />
      <path stroke-linecap="round" stroke-linejoin="round" d="m22 3-8.646 8.646a.5.5 0 0 1-.708 0L9.354 8.354a.5.5 0 0 0-.707 0L2 15" />
      <path stroke-linecap="round" stroke-linejoin="round" d="M4 18v3" />
      <path stroke-linecap="round" stroke-linejoin="round" d="M8 14v7" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_line(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <path d="m19 9-5 5-4-4-3 3" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_area(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <path d="M7 11.207a.5.5 0 0 1 .146-.353l2-2a.5.5 0 0 1 .708 0l3.292 3.292a.5.5 0 0 0 .708 0l4.292-4.292a.5.5 0 0 1 .854.353V16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1z" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_scatter(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="7.5" cy="7.5" r=".5" fill="currentColor" />
      <circle cx="18.5" cy="5.5" r=".5" fill="currentColor" />
      <circle cx="11.5" cy="11.5" r=".5" fill="currentColor" />
      <circle cx="7.5" cy="16.5" r=".5" fill="currentColor" />
      <circle cx="17.5" cy="14.5" r=".5" fill="currentColor" />
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_bubble(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="8" cy="8" r="3" fill="currentColor" opacity="0.3" />
      <circle cx="16" cy="6" r="2" fill="currentColor" opacity="0.3" />
      <circle cx="12" cy="14" r="4" fill="currentColor" opacity="0.3" />
      <circle cx="18" cy="16" r="2.5" fill="currentColor" opacity="0.3" />
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_pie(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M21 12c.552 0 1.005-.449.95-.998a10 10 0 0 0-8.953-8.951c-.55-.055-.998.398-.998.95v8a1 1 0 0 0 1 1z" />
      <path d="M21.21 15.89A10 10 0 1 1 8 2.83" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_donut(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M21 12a9 9 0 1 1-9-9" />
      <path d="M21 12a9 9 0 0 0-9-9" />
      <circle cx="12" cy="12" r="4" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_funnel(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 4h18l-3 5H6L3 4Z" />
      <path d="M6 9h12l-2.5 4H8.5L6 9Z" />
      <path d="M8.5 13h7l-2 4h-3l-2-4Z" />
      <path d="M10.5 17h3v3h-3v-3Z" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_heatmap(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect x="3" y="3" width="5" height="5" rx="0.5" opacity="0.3" />
      <rect x="9.5" y="3" width="5" height="5" rx="0.5" opacity="0.7" />
      <rect x="16" y="3" width="5" height="5" rx="0.5" opacity="1.0" />
      <rect x="3" y="9.5" width="5" height="5" rx="0.5" opacity="0.6" />
      <rect x="9.5" y="9.5" width="5" height="5" rx="0.5" opacity="0.4" />
      <rect x="16" y="9.5" width="5" height="5" rx="0.5" opacity="0.8" />
      <rect x="3" y="16" width="5" height="5" rx="0.5" opacity="0.9" />
      <rect x="9.5" y="16" width="5" height="5" rx="0.5" opacity="0.5" />
      <rect x="16" y="16" width="5" height="5" rx="0.5" opacity="0.2" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_histogram(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <rect x="6" y="14" width="3" height="3" rx="0.5" />
      <rect x="9" y="10" width="3" height="7" rx="0.5" />
      <rect x="12" y="6" width="3" height="11" rx="0.5" />
      <rect x="15" y="9" width="3" height="8" rx="0.5" />
      <rect x="18" y="13" width="3" height="4" rx="0.5" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_waterfall(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 3v16a2 2 0 0 0 2 2h16" />
      <rect x="6" y="5" width="3" height="6" rx="0.5" />
      <rect x="10" y="8" width="3" height="5" rx="0.5" />
      <rect x="14" y="11" width="3" height="3" rx="0.5" />
      <rect x="18" y="6" width="3" height="11" rx="0.5" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_gauge(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M5.636 18.364A9 9 0 1 1 18.364 5.636" />
      <path d="M12 12l4-6" stroke-linecap="round" />
      <circle cx="12" cy="12" r="1.5" fill="currentColor" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_progress(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect x="3" y="9" width="18" height="6" rx="3" opacity="0.3" />
      <rect x="3" y="9" width="12" height="6" rx="3" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_trend(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect x="2" y="3" width="20" height="18" rx="2" />
      <text x="12" y="13" text-anchor="middle" font-size="8" font-weight="bold" fill="currentColor" stroke="none">42</text>
      <path d="M10 16l2-2 2 2" stroke-linecap="round" stroke-linejoin="round" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_kpi(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect x="2" y="3" width="20" height="18" rx="2" />
      <text x="12" y="15" text-anchor="middle" font-size="10" font-weight="bold" fill="currentColor" stroke="none">42</text>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def chart_sparkline(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 17l3-4 3 2 4-8 4 5 4-3" stroke-linecap="round" stroke-linejoin="round" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def cog_6_tooth(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
      <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def plus(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M5 12h14"/>
      <path d="M12 5v14"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def blocks(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M10 22V7a1 1 0 0 0-1-1H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5a1 1 0 0 0-1-1H2"/>
      <rect x="14" y="2" width="8" height="8" rx="1"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def rotate_ccw(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
      <path d="M3 3v5h5"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def magnifying_glass(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m21 21-4.34-4.34"/>
      <circle cx="11" cy="11" r="8"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def squares_2x2(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <rect width="18" height="18" x="3" y="3" rx="2"/>
      <path d="M3 12h18"/>
      <path d="M12 3v18"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def document_text(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/>
      <polyline points="14 2 14 8 20 8"/>
      <line x1="16" x2="8" y1="13" y2="13"/>
      <line x1="16" x2="8" y1="17" y2="17"/>
      <line x1="10" x2="8" y1="9" y2="9"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def heading(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M6 12h12"/>
      <path d="M6 4v16"/>
      <path d="M18 4v16"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def link_icon(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def exclamation_circle(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="12" cy="12" r="10"/>
      <line x1="12" x2="12" y1="8" y2="12"/>
      <line x1="12" x2="12.01" y1="16" y2="16"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def trash(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M3 6h18"/>
      <path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/>
      <path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def globe(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <circle cx="12" cy="12" r="10"/>
      <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>
      <path d="M2 12h20"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def robot(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M12 8V4H8"/>
      <rect width="16" height="12" x="4" y="8" rx="2"/>
      <path d="M2 14h2"/>
      <path d="M20 14h2"/>
      <path d="M15 13v2"/>
      <path d="M9 13v2"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def send(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/>
      <path d="m21.854 2.147-10.94 10.939"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def code_braces(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5a2 2 0 0 0 2 2h1"/>
      <path d="M16 21h1a2 2 0 0 0 2-2v-5a2 2 0 0 1 2-2 2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def sparkles(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"/>
      <path d="M20 2v4"/>
      <path d="M22 4h-4"/>
      <circle cx="4" cy="20" r="2"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def corner_down_right(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="m15 10 5 5-5 5"/>
      <path d="M4 4v7a4 4 0 0 0 4 4h12"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global)

  def wrench(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.106-3.105c.32-.322.863-.22.983.218a6 6 0 0 1-8.259 7.057l-7.91 7.91a1 1 0 0 1-2.999-3l7.91-7.91a6 6 0 0 1 7.057-8.259c.438.12.54.662.219.984z"/>
    </.svg_outline>
    """
  end

  attr(:rest, :global,
    default: %{
      "stroke-width": "1.5",
      class: "w-6 h-6",
      fill: "none",
      stroke: "currentColor",
      viewBox: "0 0 24 24"
    }
  )

  def brain(assigns) do
    ~H"""
    <.svg_outline {@rest}>
      <path d="M12 18V5"/>
      <path d="M15 13a4.17 4.17 0 0 1-3-4 4.17 4.17 0 0 1-3 4"/>
      <path d="M17.598 6.5A3 3 0 1 0 12 5a3 3 0 1 0-5.598 1.5"/>
      <path d="M17.997 5.125a4 4 0 0 1 2.526 5.77"/>
      <path d="M18 18a4 4 0 0 0 2-7.464"/>
      <path d="M19.967 17.483A4 4 0 1 1 12 18a4 4 0 1 1-7.967-.517"/>
      <path d="M6 18a4 4 0 0 1-2-7.464"/>
      <path d="M6.003 5.125a4 4 0 0 0-2.526 5.77"/>
    </.svg_outline>
    """
  end
end
