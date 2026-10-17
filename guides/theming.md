# Theming

Lotus Web ships with two themes, each in light and dark:

* **Lotus** (`:lotus`), the default: white surfaces on a soft pink page, pink
  accents and Inter.
* **Sumi** (`:sumi`), the design system of [Hattori AI](https://hattori.ai):
  ink on warm paper, one blade orange accent, Outfit for the interface and
  Cormorant Garamond for titles, hairlines instead of shadows and nearly
  square corners. Charts and the SQL editor's syntax colours follow it too.

Light, dark and system stay separate from the theme: every theme has both.

## Choosing the theme

Pass `:theme` to `lotus_dashboard/2`:

```elixir
scope "/" do
  pipe_through [:browser, :require_authenticated_user]

  lotus_dashboard "/lotus", theme: :sumi
end
```

The theme applies to the dashboard and to its public dashboards.

People can also pick a theme themselves in the appearance menu (the sun,
moon or screen icon in the header), under **Theme**. Their choice is kept in
their browser, next to their light or dark choice, and wins over the
`:theme` option. Someone who never picks one sees the theme you set.

## Choosing the themes on offer

Both themes are on offer by default. To offer fewer, pass `:themes`:

```elixir
lotus_dashboard "/lotus", themes: [:lotus]
```

With a single theme, the appearance menu has no **Theme** section, and a
choice a browser kept from before is ignored. Without `:theme`, the dashboard
opens in the first theme of the list, so `themes: [:sumi]` gives a Sumi-only
dashboard. A `:theme` that is not in `:themes` fails the compile.

## Overriding colours

To bring Lotus closer to your brand without writing a theme, override single
colours with `:theme_colors`, a map from a colour token to a hex colour:

```elixir
lotus_dashboard "/lotus",
  theme_colors: %{
    "pink-500" => "#0ea5e9",
    "pink-600" => "#0284c7",
    "pink-700" => "#0369a1",
    "canvas" => "#f0f9ff",
    "logo-petal" => "#0ea5e9"
  }
```

The overrides apply over whichever theme is showing, so they also hold when
someone switches to the other theme. Values must be hex colours (`#0ea5e9` or
`#0af`); the router checks the map when it compiles and refuses unknown
tokens and other values.

The overrides are rendered in a `<style>` element in the page head. If your
app sends a Content Security Policy, pass `:csp_nonce_assign_key` (see
[Installation](installation.md)) so that the element carries your style
nonce.

### Colour tokens

Lotus uses Tailwind colour classes, and a theme sets the colours behind them.
The scales take the steps `50`, `100`, `200`, `300`, `400`, `500`, `600`,
`700`, `800`, `900` and `950`, so a token is `gray-200` or `pink-600`.

| Scale | Used for |
| --- | --- |
| `gray` | Surfaces, borders and text. In light mode the low steps are surfaces and lines and the high steps are text; dark mode is the other way round (`gray-800` cards and the navigation bar, `gray-700` dashboard cards and inputs). |
| `pink` | The accent: primary buttons, links, the active tab, selections and focus. |
| `zinc` | Tooltips and a few form controls. |
| `indigo` | Links in tables. |
| `rose` | Error borders and focus of invalid fields. |

| Token | Used for |
| --- | --- |
| `white` | Light surfaces: cards, the navigation bar, menus. |
| `black` | Ink: the darkest text and the body in dark mode. |
| `canvas`, `canvas-dark` | The page behind the cards, light and dark. |
| `editor-light`, `editor-dark` | The SQL editor and its toolbar. |
| `input-dark` | Inputs in dark mode. |
| `text-light`, `text-dark` | Page titles and the main text. |
| `logo-ink`, `logo-ink-dark` | The mark's ink petals, light and dark. |
| `logo-petal` | The mark's coloured petal and the page loading bar. |

Status colours (green success, red errors, amber warnings, blue info) are not
tokens: they carry meaning and stay the same in every theme.

### What a theme sets beyond colours

Fonts, corner radii and shadows belong to a theme and cannot be overridden
with `:theme_colors`. Sumi sets Outfit and Cormorant Garamond, 2px and 4px
corners, and 1px hairlines in place of shadows. Both fonts are inlined in
the stylesheet, so a strict `font-src` needs no change.
