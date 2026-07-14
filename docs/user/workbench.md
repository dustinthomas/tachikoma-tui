# SPC Workbench — operator guide (rough)

Day-to-day use of the multi-chart **SPC / WECO workbench** terminal app.

> Keys can change while the product is still evolving.  
> Full tables: [../src/spc-workbench.md](../src/spc-workbench.md) · Flux: [../ROADMAP.md](../ROADMAP.md)

---

## What this app is for

Use the workbench to:

- Watch **control charts** (I-MR, X̄-R/S, attribute types) in a multi-chart dashboard  
- Flag **WECO / Western Electric** run-rule violations and **out-of-spec** points  
- Set **spec limits** (USL / Target / LSL) and review **capability (Cpk)**  
- Keep a **chart library**, import **CSV** series, save/load **JSON sessions**  
- Map multi-column data via a **SharedTable** + **builder** (explicit rematerialize)

It is **keyboard-first**. Mouse works on the main plot for pan/zoom/hover; secondary (MR/R/s) canvas is display-only.

---

## Mental model (short)

```text
Session
├── Charts          each has its own series, limits mode, WECO toggles, specs, viewport
├── Tools registry  master list of tool ids (assign to charts in the builder)
├── Shared table    optional in-memory spreadsheet-like data (from CSV/session)
└── Filters         show only charts matching tool / type / owner
```

**Materialize:** charts display a **series** (`values`). The SharedTable is a separate source. Changing table cells does **not** rebuild the chart until you **Apply** in the builder (`a`) or rematerialize from the table grid (`r`).

---

## Dashboard

This is the home screen after launch (and after closing library/builder/etc.).

### Navigate charts

| Key | Action |
|-----|--------|
| `[` `]` | Previous / next **active** chart |
| `←` `→` | Pan the viewport left / right |
| `r` / `z` | Reset viewport (full X range + auto Y fit) |
| Mouse | Hover tooltip, drag pan, wheel zoom, click to select a point |

### Live data

| Key | Action |
|-----|--------|
| `p` | Pause / resume **session** tick-driven live |
| **`g` / `G`** | Toggle **this chart’s** live append on/off |

**Important:** Live is **only** `g`/`G`. The key **`L` is for LSL** (lower spec limit), not live.

Seeded demos usually start with live enabled on charts. Successful **CSV import** turns live **off** for that chart and pauses the session.

### Specs and WECO

| Key | Action |
|-----|--------|
| `u` / `t` / `l` | Edit USL / Target / LSL (prompt) |
| `s` | Clear all **spec** limits on the active chart |
| `1` … `8` | Toggle WECO rule 1–8 on the active chart (no menu needed) |
| `c` | Open **Config** → Rules (WECO descriptions + toggles) |
| `v` | Open **Config** → Lines (CL / σ / specs visibility + styles) |
| `o` | Open **Config** → Visual (connectors, secondary canvas, …) |
| **`e`** | Open **Config** → **Saved** (named configs + file save/load) |

### Config menu (full page)

One page for how the graph looks and which WECO rules fire. **Not** an overlay;
**not** a separate “Graph Presets” page. Esc/`q` closes to the dashboard (does
not quit). Section jumps: `c` / `v` / `o` / `e` or Tab.

| Section | What you edit |
|---------|----------------|
| **Rules** | WECO-1…8 on the **active** chart |
| **Lines** | CL / ±σ / specs on/off and line style |
| **Visual** | Series connectors, secondary canvas, … |
| **Saved** | Named snapshots of the whole set + portable JSON files |

Toggles apply **immediately**. Loading a saved config is the batch apply.

#### Config → Saved

| Key | Action |
|-----|--------|
| `s` | Name prompt — save/upsert current set into the **session** list |
| `w` | Path prompt — **file-save** graph config JSON |
| `W` | Path prompt — **file-load** → apply → back to dashboard |
| `↑` `↓` | Select a named config |
| Enter / `l` / `a` / Space | Load selected → **dashboard** |
| `d` then `y` | Delete named config (does **not** delete a chart) |
| Esc / `q` | Close Config |

**What a config includes:** line visibility, line styles, visual prefs, WECO
enable map. **Not** series values, not USL/Target/LSL numbers, not viewport.

**WECO on load:** applies to the **active chart** and to session defaults for
**new** charts — not every chart already in the library.

**Same keys, different modes (easy to mix up):**

| Key | Dashboard | Config | Library |
|-----|-----------|--------|---------|
| `s` | Clear **specs** | Name-save config | — |
| `w` / `W` | — | Graph **config** file | Whole **session** JSON |
| `e` | Config → Saved | Jump Saved | Export CSV |
| `c` | Config → Rules | Jump Rules | Clone chart |

### Open other pages

| Key | Opens |
|-----|--------|
| `m` | Chart **library** |
| `b` | Chart **builder** (active chart form) |
| `x` | **Tools** registry |
| `d` | **SharedTable** grid |
| `f` | Filter prompt / clear filters |
| `?` / `h` | Help |
| `k` | Keymap |
| `q` / Esc | **Quit** (dashboard only) |

### Dual secondary chart (MR / R / s)

For I-MR, X̄-R, and X̄-S, the **active** plot can show a second canvas under the primary:

- Toggle preference under Config → Visual (**`o`**) → “Secondary canvas”
- Default is **on**
- On short terminals with three panes, the UI may **temporarily hide neighbor panes** so the dual plot fits — not a permanent “focused mode”
- Mouse still applies to the **primary** only

---

## Chart library (`m`)

List of charts in the session.

| Key | Action |
|-----|--------|
| `↑` `↓` | Move selection |
| Enter | Make selected chart active → return to dashboard |
| `a` | Add empty chart |
| `c` | Clone selected (**library only** — on dashboard `c` is config) |
| `d` then `y` | Delete (cannot delete the last remaining chart) |
| `n` | Rename |
| **`i`** | Import CSV (path prompt) |
| **`e`** | Export selected chart series as CSV |
| **`w` / `W`** | Save / load JSON workbench session |
| Esc / `q` | Back to dashboard (**does not quit**) |

Mouse: click rows to select; double-click can activate (when library mouse chrome is available).

While a path/name **prompt** is open: type normally; **`q` is a character in the path**, not quit. Enter applies; Esc cancels.

---

## Chart builder (`b`)

Edit definition of the **active** chart.

Typical fields: name, chart type, value / n / tool / time / lot columns, tools (comma-separated ids), owner, subgroup size, limits mode, manual CL/UCL/LCL.

| Key | Action |
|-----|--------|
| `↑` `↓` | Move field |
| Enter / Space | Edit string field, or toggle/cycle special fields |
| `y` | Cycle chart type only |
| `a` | Apply + materialize from SharedTable when table has data |
| `1`…`8` | Toggle WECO rules on this chart |
| Esc / `q` / `b` | Close → dashboard |

Subgroup size is clamped **2–25**. Invalid edits keep the previous value.

---

## Tools registry (`x`)

Master list of tools (`id` + description) for the **session**.

| Key | Action |
|-----|--------|
| `↑` `↓` | Move selection |
| `a` | Add tool |
| `n` | Edit description |
| `d` then `y` | Delete tool |
| Enter | Set tool filter to this id → dashboard |
| Esc / `q` | Close |

**Assigning tools to a chart** is done in the **builder** (`Tools (csv)` field), not only by creating registry entries. Filters match **per-chart** tool lists.

---

## SharedTable grid (`d` from dashboard)

Inspect/edit the in-memory table (not Excel).

| Key | Action |
|-----|--------|
| Arrows | Move cell |
| PgUp / PgDn | Page rows |
| Enter | Edit cell / commit edit |
| Esc (editing) | Cancel edit |
| **`r` / `R`** | Rematerialize **active** chart from table |
| Esc / `q` | Close → dashboard |

Empty table: import CSV via library **`i`**, or load a session that includes a table.

**Mode note:** library **`d`** means *delete chart*; dashboard **`d`** means *open table*. Different modes, different meaning.

---

## Filters (`f`)

Narrow which charts appear on the dashboard (tool / type / owner, depending on prompt flow). Clear filters when the dashboard looks “empty” after filtering.

If the active chart is filtered out, the UI follows the product policy for picking another visible chart (see developer docs if behavior surprises you).

---

## Chart types (operator view)

| Type | Primary idea | Secondary (if dual on) |
|------|----------------|-------------------------|
| **I-MR** | Individuals | Moving range |
| **X̄-R** | Subgroup means | Ranges |
| **X̄-S** | Subgroup means | Std devs |
| **p / np / c / u** | Attribute / count charts | No secondary series |

Use the builder to set type and column maps. For X̄ with table grouping, set **lot** (or group) column and materialize.

---

## Reading the display

Rough guide to markers and panels (exact glyphs depend on theme/render):

- **Control limits** — CL, UCL, LCL (auto from data or manual)
- **σ zones** — optional zone lines via visual/line prefs
- **WECO markers** — points that break enabled rules
- **OOS** — outside USL/LSL (specs), distinct from control-limit OOC
- **Cpk band / color** — capability when specs allow a computation
- **Side panel / footer** — stats, secondary bar (e.g. MR̄), last event messages

Use **`?`** in-app when unsure; update this guide if in-app help diverges.

---

## Suggested workflows

### A. Explore the demo

1. `spc_workbench_demo()`
2. `[` `]` · `1`–`8` · mouse hover · `?`

### B. Import a measurement file

1. Dashboard → **`m`** → **`i`** → path to CSV with `Value`
2. Inspect chart; adjust specs (`u`/`t`/`l`); toggle WECO
3. Optional: **`e`** export; **`w`** save session

### C. Multi-column fab sheet

1. Import multi-column CSV (fills SharedTable + series when `Value` present)
2. **`b`**: set chart type, columns, tools, Apply (`a`)
3. Or **`d`**: edit cells, then **`r`** rematerialize

### D. Live monitoring

1. `spc_workbench()` (not paused)
2. **`g`** per chart; **`p`** to freeze everything

More detail on files: [Data import & export](data-import-export.md)

---

## Common confusions

| Confusion | Reality |
|-----------|---------|
| `L` for live | No — **`g`**. `L` is LSL. |
| `q` in a path prompt quits | No — it types the letter `q`. Esc cancels. |
| Edit table → chart updates | No — rematerialize with builder **`a`** or table **`r`**. |
| Tools registry assigns charts | No — registry is the master list; builder sets `ch.tools`. |
| `d` always means table | No — dashboard `d` = table; **library** `d` = delete chart; **Config Saved** `d` = delete named config. |
| Neighbor charts show MR dual | No — dual secondary is **active chart only**. |
| Three overlays `c`/`v`/`o` + presets `e` | **One Config page** with four sections; deep-link keys still work. |
| Dashboard `s` saves a config | No — dashboard `s` **clears specs**. Name-save is Config **`s`**. |
| Library `w` vs Config `w` | Library = whole **session** (charts + data). Config = **graph config** file only. |
| Load config rewrites all charts’ WECO | No — **active chart** + session defaults for new charts only. |
