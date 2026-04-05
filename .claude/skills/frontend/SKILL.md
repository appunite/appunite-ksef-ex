---
name: frontend
description: Generate frontend UI code matching project patterns — Phoenix components, shadcn/ui tokens, selective DaisyUI. Use when building LiveView pages, components, or templates.
---

You are generating frontend code for a Phoenix LiveView app that uses a **hybrid styling approach**: custom Phoenix components with shadcn/ui color tokens as the primary system, with DaisyUI 5 used selectively for interactive behaviors.

## Rules

1. **Reuse existing components** from `CoreComponents` and `InvoiceComponents` before creating new ones
2. **Use shadcn/ui semantic color tokens** — NEVER use raw Tailwind colors like `gray-500`, `red-600`, `blue-400`
3. **DaisyUI classes only for interactive behaviors** (dropdown, loading, toast, modal, collapse, tabs) — not for basic layout or styling
4. **Follow Phoenix.Component conventions**: `attr` declarations, `slot` definitions, `@spec` on every function, `~H` sigil
5. **Heroicons** via `<.icon name="hero-*" />` — outline by default, add `-solid` or `-mini` suffix for variants
6. **Tailwind CSS 4** for layout (flexbox, grid, spacing, sizing) — no `tailwind.config.js`, config lives in `app.css`
7. **No custom CSS** — use utility classes only. The project neutralises DaisyUI shadows/radius so Tailwind utilities win
8. **LiveView patterns**: use `phx-click`, `phx-change`, `phx-submit`, `JS` commands for interactivity

## Available Custom Components (always prefer these)

### CoreComponents (`KsefHubWeb.CoreComponents`)

| Component | Key attrs | Notes |
|-----------|-----------|-------|
| `<.badge variant="success">` | variant: success\|warning\|error\|info\|muted\|default | Inline colored pill |
| `<.button variant="primary">` | variant: primary\|outline\|ghost\|destructive\|success\|warning, size: default\|sm\|icon | Auto-renders `<.link>` when `navigate`/`patch`/`href` given |
| `<.card>` | class, padding (default "p-6") | Rounded border container |
| `<.auth_card title="...">` | title, footer slot | Centered card for auth pages |
| `<.input field={@form[:name]}>` | type: text\|select\|checkbox\|textarea\|date\|email\|..., label, errors | Handles FormField, includes error display |
| `<.simple_form for={@form}>` | for, as, actions slot | Form wrapper with spacing |
| `<.table id="..." rows={@items}>` | id, rows, row_click, col slots (label, class), action slot | Supports LiveStream |
| `<.header>` | subtitle slot, actions slot | Page header with border-bottom |
| `<.pagination>` | page, per_page, total_count, total_pages, base_url, params, noun | Prev/Next with page info |
| `<.multi_select>` | id, label, options (list of {label, value}), selected, on_toggle, field, searchable, open | Linear-style filter picker |
| `<.icon name="hero-x-mark">` | name, class (default "size-4") | Heroicon span |
| `<.flash kind={:info}>` | kind: :info\|:warning\|:error, flash, title | Toast notification |
| `<.error>` | inner_block | Red error text with icon |
| `<.list>` | item slots with title attr | Key-value data list |
| `<.file_upload_dropzone>` | upload, label | Drag-and-drop file input |
| `<.logo href="/">` | href | App logo with icon+text |
| `<.nav_item_list>` | items, current_path | Sidebar navigation list |

### InvoiceComponents (`KsefHubWeb.InvoiceComponents`)

| Component | Key attrs |
|-----------|-----------|
| `<.type_badge type={:income}>` | type: :income\|:expense |
| `<.status_badge status={:pending}>` | status: :pending\|:approved\|:rejected\|:duplicate, label |
| `<.category_badge category={@cat}>` | category map (emoji, name) |
| `<.tag_list tags={@tags}>` | tags list |
| `<.payment_badge status={:paid}>` | status: :paid\|:pending\|:voided |
| `<.extraction_badge status={:partial}>` | status, duplicate_status |
| `<.needs_review_badge>` | prediction_status, duplicate_status, extraction_status, status |
| `<.invoice_details_table invoice={@inv}>` | invoice, show_added_by |
| `<.local_datetime at={@dt} id="ts">` | at (DateTime), id — JS hook for local tz |

Helpers: `format_date/1`, `format_amount/1`, `format_datetime/1`, `format_month/1`, `format_billing_period/2`, `display_status/1`

## Color Token System

Use these semantic tokens — they auto-adapt to light/dark theme:

```text
Backgrounds:  bg-background  bg-card  bg-popover  bg-muted  bg-shad-accent
Text:         text-foreground  text-card-foreground  text-muted-foreground  text-popover-foreground
              text-shad-primary-foreground  text-shad-accent-foreground
Borders:      border-border  border-input
Primary:      bg-shad-primary  text-shad-primary  hover:bg-shad-primary/90
Secondary:    bg-shad-secondary  text-shad-secondary-foreground
Destructive:  bg-shad-destructive  text-shad-destructive  hover:bg-shad-destructive/90
Status:       bg-success/10 text-success  border-success/20
              bg-warning/10 text-warning  border-warning/20
              bg-error/10   text-error    border-error/20
              bg-info/10    text-info     border-info/20
Focus:        focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring
Hover:        hover:bg-shad-accent hover:text-shad-accent-foreground
Disabled:     disabled:pointer-events-none disabled:opacity-50
```

**IMPORTANT**: `primary`, `secondary`, `accent` without the `shad-` prefix are DaisyUI theme colors. Use `shad-primary`, `shad-secondary`, `shad-accent` for the shadcn token variants. Status colors (`success`, `warning`, `error`, `info`) are shared between both systems.

## DaisyUI 5 Quick Reference (use when needed)

Only reach for DaisyUI when building interactive behavior that custom components don't cover:

```text
dropdown:    dropdown dropdown-content dropdown-end dropdown-start dropdown-top dropdown-hover dropdown-open
loading:     loading loading-spinner loading-dots loading-ring loading-bars (loading-xs..xl)
breadcrumbs: breadcrumbs > ul > li > a
toast:       toast toast-start toast-center toast-end toast-top toast-bottom
checkbox:    checkbox checkbox-{color} checkbox-{size}
collapse:    collapse collapse-title collapse-content collapse-arrow collapse-plus
modal:       modal modal-box modal-action modal-backdrop modal-open (use HTML dialog)
tabs:        tabs tab tab-content tabs-box tabs-border tab-active
alert:       alert alert-info alert-success alert-warning alert-error alert-soft alert-outline
menu:        menu menu-title menu-horizontal menu-vertical (menu-xs..xl)
steps:       steps step step-icon step-{color}
tooltip:     tooltip tooltip-content tooltip-top tooltip-bottom tooltip-{color}
toggle:      toggle toggle-{color} toggle-{size}
badge:       badge badge-{color} badge-outline badge-soft (but prefer custom <.badge>)
stats:       stats stat stat-title stat-value stat-desc
progress:    progress progress-{color}
swap:        swap swap-on swap-off swap-rotate swap-flip
join:        join join-item join-horizontal join-vertical
drawer:      drawer drawer-toggle drawer-content drawer-side drawer-overlay
dock:        dock dock-label dock-active (dock-xs..xl)
skeleton:    skeleton skeleton-text
divider:     divider divider-vertical divider-horizontal
kbd:         kbd (kbd-xs..xl)
```

Colors available for DaisyUI modifiers: neutral, primary, secondary, accent, info, success, warning, error
Sizes: xs, sm, md, lg, xl

## New Component Template

When creating a new Phoenix component:

```elixir
@doc """
Brief description of what this renders.

## Examples

    <.my_component attr="value">Content</.my_component>
"""
attr :class, :string, default: nil
attr :rest, :global
slot :inner_block, required: true

@spec my_component(map()) :: Phoenix.LiveView.Rendered.t()
def my_component(assigns) do
  ~H"""
  <div class={["base-classes", @class]} {@rest}>
    {render_slot(@inner_block)}
  </div>
  """
end
```

## Common Patterns

**Page layout**: `<.header>` at top, then `<.card>` sections with content
**Data display**: `<.table>` with `:col` slots, or `<.list>` for key-value
**Forms**: `<.simple_form>` wrapping `<.input>` fields, `<:actions>` slot for buttons
**Filters**: Row of `<.multi_select>` pickers above table
**Empty states**: Centered text in `text-muted-foreground` within a card
**Loading states**: `<span class="loading loading-spinner loading-lg text-primary"></span>` (`text-primary` is DaisyUI here — correct for DaisyUI components)
**Tab bar**: `flex border-b border-border` container with `tab_class(boolean)` helper
