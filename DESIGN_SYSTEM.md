# KSeF Hub — Design System Guide

This is the authoritative spec for porting screens to the new design. The reference implementation lives in `ui_kits/admin/` (HTML/React prototype). When in doubt, read the prototype — don't invent.

**How to use this doc with Claude Code / AI handoffs:**
1. Attach this file + the prototype files (`Primitives.jsx`, `AppShell.jsx`, one target screen like `Payments.jsx`).
2. Attach a screenshot of the target screen rendered.
3. Port **one screen at a time**. Diff. Iterate. Do not request app-wide rewrites.
4. After each screen: render it side-by-side with the prototype and compare.

---

## 1. Tokens (source of truth)

All colors, type, radii, spacing come from `colors_and_type.css`. Never hardcode hex. Use CSS variables via Tailwind arbitrary values:

```
bg-[var(--card)]         text-[var(--foreground)]
border-[var(--border)]   text-[var(--muted-foreground)]
bg-[var(--accent)]       text-[var(--success)]
```

Key semantic pairs:

| Token                    | Use                                            |
|--------------------------|------------------------------------------------|
| `--background` / `--foreground` | Page body                                |
| `--card` / `--card-foreground`  | Cards, table container                   |
| `--muted` / `--muted-foreground` | Subdued surfaces & secondary text       |
| `--accent`               | Hover/selected row background                  |
| `--border` / `--input`   | All borders and input outlines                 |
| `--ring`                 | Focus ring (single ring, width 1)              |
| `--primary`              | Primary button bg (inverted)                   |
| `--brand` / `--brand-muted` | Teal accent — logos, highlights             |
| `--success/warning/destructive/info/purple` | Badge + inline semantic color |

**Typography:** `Geist` (sans) + `Geist Mono`. Body is 14px. Page H1 is 18px semibold. Do not introduce other font families or type scales.

---

## 2. The 11 rules that make it look right

These are the ones Claude Code gets wrong most often. Treat as constraints.

1. **IDs, numbers, NIPs, IBANs, references, dates, amounts → `font-mono text-xs`.** Always. The monospace rhythm is core to the identity.
2. **Amounts → `font-mono text-sm tabular-nums whitespace-nowrap text-right`.** Currency in `text-xs text-[var(--muted-foreground)] ml-1` after the number. For two-line amounts: gross on top, net below as `font-mono text-[11px] tabular-nums text-[var(--muted-foreground)]` with the word `net` in `opacity-70`.
3. **Status → always a `<Badge variant="…">`** (not a raw span). Variants: `success | warning | error | info | muted | purple | brand`. Never colored dots alone.
4. **Row density is tight.** Table cells: `px-4 py-3`. Headers: `px-4 py-2.5 text-xs uppercase tracking-wide text-[var(--muted-foreground)] font-medium` on `bg-[var(--muted)]/50`. No extra padding "to breathe."
5. **Row hover is `bg-[var(--accent)]`.** Selected row gets the same. A trailing chevron may appear on hover only: `opacity-0 group-hover:opacity-100`.
6. **Empty state string: "No data for selected period".** Centered, `text-sm text-[var(--muted-foreground)]`, `py-12`. Don't invent copy.
7. **Bulk action bar on selection**: inverted — `bg-[var(--foreground)] text-[var(--background)]` above the table header row, with count · summary · actions (secondary inline buttons, not full `Button` components inside).
8. **Tabs above tables**: underline style. Active tab has a 2px bottom bar (`bg-[var(--foreground)]`), inactive is `text-[var(--muted-foreground)]`. Each tab shows a count pill (see §4).
9. **Summary tiles are always 3-up** (`grid grid-cols-1 sm:grid-cols-3 gap-3 mb-5`). Structure: uppercase label, `text-2xl font-semibold tabular-nums` value, muted sub-line. Currency suffix in `font-mono text-[var(--muted-foreground)]`.
10. **Focus rings are thin.** `focus:ring-1 focus:ring-[var(--ring)]`, never `ring-2` or `ring-offset-*`. No glowy focus.
11. **Interaction feel is `transition-all` + `active:scale-[0.98]`, nothing else.** All interactive elements animate with `transition-all` (150ms ease-out default). Hover = `opacity-90` on filled variants, `bg-[var(--accent)]` on outline/ghost. Pressed = `active:scale-[0.98]` on buttons; outline/ghost also get `active:opacity-80`. Row hover stays `bg-[var(--accent)]` — no scale. Never add box-shadow lifts, color shifts, or `hover:-translate-*` transforms.

---

## 3. Component API contract

Use these exact components from `Primitives.jsx`. Don't re-implement.

### `<Button variant size>`
- `variant`: `primary | outline | ghost | destructive | brand`
- `size`: `default | sm | icon`
- Heights are fixed: `default h-9`, `sm h-7`, `icon h-9 w-9`
- Always `rounded-md` (not pill, not square)
- Icon before label with `gap-2`
- Base always includes: `transition-all active:scale-[0.98] focus:ring-1 focus:ring-[var(--ring)]`
- Filled variants (`primary`, `destructive`, `brand`): `hover:opacity-90`
- Unfilled variants (`outline`, `ghost`): `hover:bg-[var(--accent)]` + `active:opacity-80`

### `<Badge variant>`
- Variants as listed in rule 3
- Always `px-2 py-0.5 rounded-md text-xs font-medium border whitespace-nowrap`
- Shows with a tinted background (10%) + same-hue border (20%). **Never solid-fill.**

### `<Card padding>`
- `rounded-xl border border-[var(--border)] bg-[var(--card)]`
- Default padding is `p-6`; pass `padding="p-0"` for embedded lists

### `<Input label error>`
- 9px tall field, `rounded-md`, thin focus ring
- Error state uses `--destructive` border + inline error row

### `<Icon name size>`
- Fixed 24×24 viewBox, `stroke="currentColor" strokeWidth="1.5"`. Size in px.
- Only use names present in `Primitives.jsx`. If you need a new one, add it there — don't inline SVGs elsewhere.

### `<PageHeader title subtitle actions>`
- Every page starts with this. Bottom border, `mb-6`.
- Actions are right-aligned; primary always rightmost.

---

## 4. Recurring patterns (copy these verbatim)

### Status tabs with count pills
```jsx
<div className="-mt-2 mb-5 border-b border-[var(--border)] flex items-center">
  {tabs.map(t => {
    const active = value === t.id;
    return (
      <button key={t.id} onClick={() => onChange(t.id)}
        className={`relative -mb-px h-10 px-4 text-sm flex items-center gap-2
          ${active ? "text-[var(--foreground)] font-medium" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"}`}>
        {t.label}
        <span className={`inline-flex items-center justify-center min-w-[20px] h-[18px] px-1
          rounded text-[11px] font-mono tabular-nums
          ${active ? "bg-[var(--foreground)] text-[var(--background)]" : "bg-[var(--muted)] text-[var(--muted-foreground)]"}`}>
          {counts[t.id]}
        </span>
        {active && <span className="absolute left-0 right-0 bottom-0 h-[2px] bg-[var(--foreground)]" />}
      </button>
    );
  })}
</div>
```

### Table shell
```jsx
<div className="rounded-lg border border-[var(--border)] overflow-hidden bg-[var(--card)]">
  {/* optional bulk bar */}
  <div className="overflow-x-auto">
    <table className="w-full text-left">
      <thead className="bg-[var(--muted)]/50 border-b border-[var(--border)]">
        <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)]">
          <th className="px-4 py-2.5 font-medium">…</th>
        </tr>
      </thead>
      <tbody>{…}</tbody>
    </table>
  </div>
  <div className="flex items-center justify-between px-4 py-2.5 border-t border-[var(--border)] text-xs text-[var(--muted-foreground)]">
    <span>Showing 1–N of N items</span>
    <div className="flex items-center gap-1">…pagination…</div>
  </div>
</div>
```

### Bulk action bar (appears when rows selected)
```jsx
<div className="flex items-center justify-between px-4 py-2.5 bg-[var(--foreground)] text-[var(--background)] border-b border-[var(--border)]">
  <div className="flex items-center gap-3 text-sm">
    <span className="font-medium tabular-nums">{n} selected</span>
    <span className="opacity-60">·</span>
    <span className="font-mono text-xs tabular-nums opacity-80">{totalPLN} PLN</span>
  </div>
  <div className="flex items-center gap-2">
    {/* inline buttons, NOT full <Button> — h-7 px-2.5 text-xs rounded-md */}
  </div>
</div>
```

### Row checkbox (tri-state header)
Native `<input type="checkbox">` with `indeterminate` set via ref. `w-4 h-4 rounded border-[var(--border)] accent-[var(--foreground)] focus:ring-1 focus:ring-[var(--ring)]`.

### Summary tiles
```jsx
<Card>
  <div className="text-xs text-[var(--muted-foreground)] uppercase tracking-wide">{label}</div>
  <div className="mt-1 text-2xl font-semibold tabular-nums">
    {value}
    <span className="text-sm font-mono text-[var(--muted-foreground)] ml-1.5">{unit}</span>
  </div>
  <div className="text-xs text-[var(--muted-foreground)] mt-1">{sub}</div>
</Card>
```

### Toast
Bottom-right, auto-dismiss 3.2s. `fixed bottom-6 right-6 z-50 px-3.5 py-2.5 rounded-lg shadow-lg border bg-[var(--card)]`. Icon + text, no close button.

---

## 5. Typography inventory (table-specific)

The 4-tier rule — use this to decide any unlisted element:
- `text-sm (14px) sans` — human-readable primary text (names, titles)
- `text-xs (12px) mono tabular-nums` — identifiers, dates, currency codes, copy-paste strings
- `text-[11px] mono tabular-nums muted` — secondary line under a primary (NIP, IBAN, net amount)
- `text-[10px]` — tertiary labels (date sub-labels, confidence %, void reasons)

### Table header (`<thead>`)
| Element | Size | Weight | Notes |
|---------|------|--------|-------|
| Column label | `text-xs` | `font-medium` | `uppercase tracking-wide text-muted-foreground` |
| Header row | `py-2.5` | — | `bg-muted/50 border-b` |

### Table body (`<tbody>`)
| Cell content | Size | Font | Notes |
|-------------|------|------|-------|
| Primary text (seller, counterparty name) | `text-sm` | sans | truncated |
| IDs / invoice numbers / references | `text-xs` | mono | `tabular-nums` |
| Secondary mono line (NIP, IBAN under name) | `text-[11px]` | mono | `text-muted-foreground` |
| Amount (gross / primary) | `text-sm` | mono | `tabular-nums whitespace-nowrap leading-tight` |
| Currency suffix | `text-xs` | — | `text-muted-foreground ml-1` |
| Net amount (under gross) | `text-[11px]` | mono | `tabular-nums text-muted-foreground` |
| Date | `text-xs` | mono | `tabular-nums text-muted-foreground whitespace-nowrap` |
| Status / Kind badge text | `text-xs` | `font-medium` | via `<Badge>` |
| Category badge text | `text-xs` | sans | |
| Category confidence (`· 82%`) | `text-[10px]` | sans | `text-muted-foreground` |

### Above/below the table
| Element | Size | Notes |
|---------|------|-------|
| Tab label | `text-sm` | active: `font-medium` |
| Tab count pill | `text-[11px] mono` | `min-w-[20px] h-[18px]` |
| Filter chips / date picker / search | `text-xs` | `h-8` controls |
| Pagination text | `text-xs` | `text-muted-foreground` |

---

## 6. Column conventions (invoice-like tables)

Fixed column order when applicable:

`[source] Number | Seller (NIP below) | Date | Amount (gross + net) | Kind | Category | Status | Payment | [chevron]`

- **Number** cell: `font-mono text-xs truncate` in a `max-w-[200px]` td.
- **Seller** cell: seller name `text-sm truncate`, NIP below as `font-mono text-[11px] text-[var(--muted-foreground)]`.
- **Date** cell: `font-mono text-xs text-[var(--muted-foreground)] whitespace-nowrap`, formatted as `17 Apr`.
- **Amount** cell: see rule 2. Right-aligned.
- **Kind / Category**: `<Badge>` only.
- Trailing chevron column: `w-6`, `opacity-0 group-hover:opacity-100`.

---

## 7. Do / Don't

**Do**
- Reach for existing primitives first (`Badge`, `Button`, `Card`, `Input`, `Icon`).
- Keep tables dense; don't pad "for breathing room."
- Use `tabular-nums` on *every* number column and stat.
- Put unit/currency as a smaller muted suffix after the number.
- Use `rounded-md` for interactive, `rounded-xl` for cards, `rounded-lg` for table containers.

**Don't**
- Don't add gradients, emoji, drop shadows on cards, or colored left borders on rows.
- Don't add `hover:-translate-*`, shadow lifts, or color-shift hover effects on buttons — use `hover:opacity-90` (filled) or `hover:bg-[var(--accent)]` (outline/ghost) only.
- Don't use `transition-colors` on buttons — always `transition-all` so the native `:active` state animates too.
- Don't introduce solid-filled status pills (always tinted).
- Don't use `<div>`s where `<Badge>` should go.
- Don't add new colors outside the token set — compose with `color-mix(in oklch, var(--x) 10%, transparent)` if you need a faint surface.
- Don't center-align numbers or dates.
- Don't use `text-gray-*` / `text-zinc-*` / `text-neutral-*` Tailwind classes. Use `text-[var(--muted-foreground)]`.
- Don't widen focus rings or add `ring-offset`.
- Don't invent copy for empty states, tab labels, or button verbs — copy from the prototype.

---

## 8. Handoff workflow (recommended)

1. **Commit this file + the prototype** into the real repo under `docs/design-system/`.
2. **Per screen** in the real app, open a PR that links to the matching prototype file. In the PR description, paste:
   - Screenshot of prototype screen
   - Screenshot of current real screen
   - Checklist of the 11 rules from §2
3. **Ask Claude Code one screen at a time**, e.g.:
   > Port `app/views/payments/index.tsx` to match `ui_kits/admin/Payments.jsx`. Follow `docs/design-system/DESIGN_SYSTEM.md`. Reuse `Button`, `Badge`, `Card` from `app/components/ui/`. Keep existing data hooks. Output a diff, don't touch other files.
4. **Review against §2**. Almost every miss is one of those 11 rules.
