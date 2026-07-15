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
├── Params catalog  optional tool parameters (Side Stats ▸ PARAMS; fake_tool seed)
├── Shared table    optional in-memory spreadsheet-like data (from CSV/session)
└── Filters         show only charts matching tool / type / owner
```

**Materialize:** charts display a **series** (`values`). The SharedTable is a separate source. Changing table cells does **not** rebuild the chart until you **Apply** in the builder (`a`) or rematerialize from the table grid (`r`).

**Seed demos:** runners default to `seed_demos = :triple` (three stacked demos). Keep that default for day-to-day and CI. For a **single-chart tool + parameter** product walkthrough, pass `seed_demos = :fake_tool` (see [Tool parameter demo](#tool-parameter-demo-fake_tool) below). Do not flip the model/runner default without an explicit product decision.

---

## Dashboard

This is the home screen after launch (and after closing library/builder/etc.).

How many chart panes you see is controlled by **`dashboard_max_panes`** (clamped 1…3). Seed policy sets it: **`:triple` → 3**, **`:fake_tool` / `:single` / `:none` → 1**. Adding a chart via the **Add Chart** wizard can raise the budget up to 3 so new panes appear.

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
| `p` / `P` | Pause / resume **session** tick-driven live (**unchanged** — not used for params) |
| **`g` / `G`** | Toggle **this chart’s** live append on/off |

**Important:** Live is **only** `g`/`G`. The key **`L` is for LSL** (lower spec limit), not live. **`p`/`P` always pause**, even when Side Stats PARAMS is focused. **`k`/`K` always open the keymap**, even when PARAMS is focused.

Seeded demos usually start with live enabled on charts. Successful **CSV import** turns live **off** for that chart and pauses the session.

### Side Stats ▸ PARAMS (tool parameters)

When the session has a **parameter catalog** (filled by `seed_demos = :fake_tool`), Side Stats shows an interactive **`▸ PARAMS`** section (after STATS, before HOVER). Other Side Stats sections stay read-only paint.

Typical chrome under `:fake_tool`:

```text
▸ PARAMS
◆ Film-PTPECVD01
▶ 1 Thickness 1.3µm  nm
  2 Refractive Index  —
  3 HSQ Thickness  nm
```

| Key | Action |
|-----|--------|
| **`;`** | Toggle **PARAMS focus** on/off (no-op if catalog empty) |
| **`j` / `J`** | Next / previous parameter (**only while focused**) |
| **`↑` / `↓`** | Previous / next parameter (**only while focused**; otherwise no-op) |
| **`1`…`9`** | Jump to parameter index **while focused** (digits do **not** toggle WECO while focused) |
| Esc | Clear PARAMS focus (does not quit while focused) |

Selecting a parameter activates the chart whose `param` id matches that catalog entry. If no chart exists yet, the list still highlights the row and status reports **`no chart for param — press + to add`** (series are never rewritten on select).

While **unfocused**, `1`…`8` still toggle WECO rules on the active chart as before.

### Add Chart (`+` / `A`)

On the **dashboard** only:

| Key | Action |
|-----|--------|
| **`+`** or **`A`** | Open the **Add Chart** modal |

Library **`a`** remains **blank add chart** — it does **not** open this wizard.

**Modal keys** (full absorb; Esc/`q` close the modal and never quit the app):

| Key | Action |
|-----|--------|
| Tab | Toggle mode: **Param** ↔ **Analysis** |
| `↑` `↓` | Move list cursor |
| Enter / Space | Confirm |
| Esc / `q` | Cancel |

| Mode | What it adds |
|------|----------------|
| **Param** | Chart for another catalog parameter (same tool when seeded from fake_tool) |
| **Analysis** | Second analysis of the **active** chart’s parameter — v1 types: **I-MR**, **X̄-R**, **X̄-S** only |

Duplicates (same parameter id + chart type) are refused. A successful wizard add can **auto-raise** `dashboard_max_panes` up to 3 so the new pane is visible.

### Specs and WECO

| Key | Action |
|-----|--------|
| `u` / `t` / `l` | Edit USL / Target / LSL (prompt) |
| `s` | Clear all **spec** limits on the active chart |
| `1` … `8` | Toggle WECO rule 1–8 on the active chart (no menu needed) |
| `c` | Open **Config** → Rules (WECO descriptions + toggles) |
| `v` | Open **Config** → Lines (CL / σ / specs visibility + styles) |
| `o` | Open **Config** → Visual (connectors, secondary canvas, …) |
| **`e`** | Open **Config** → **Saved** (known disk configs + file explorer) |

### Config menu (full page)

One page for how the graph looks and which WECO rules fire. **Not** an overlay;
**not** a separate “Graph Presets” page. Esc/`q` closes to the dashboard (does
not quit). Section jumps: `c` / `v` / `o` / `e` or Tab.

| Section | What you edit |
|---------|----------------|
| **Rules** | WECO-1…8 on the **active** chart |
| **Lines** | CL / ±σ / specs on/off and line style |
| **Visual** | Series connectors, secondary canvas, … |
| **Saved** | List of known graph-config files + save/load via file explorer |

Toggles apply **immediately**. Loading a saved config is the batch apply.

#### Open Saved

```text
Dashboard ──v──► Config [Lines] ──Tab or e──► Saved
Dashboard ──e──► Config [Saved]   (direct)
```

#### Config → Saved (disk-first)

Configs are **portable JSON files**. The Saved tab keeps a **list of known
files** (merged with a durable index that survives restarts). Saving always
writes a file; the list tracks paths so you can re-open favorites without
retyping.

| Key | Action |
|-----|--------|
| **`s` / `w`** | **Save As** — in-TUI **file explorer** (browse dirs, type filename) |
| **`S`** | **Quick Save** — overwrite the known path (selected row or last used); if none, opens Save As |
| **`W`** | **Load** — file explorer → pick a `.json` config → apply → **dashboard** |
| **`p` / `P`** | Typed-path save / load (paste full path; secondary to the explorer) |
| `↑` `↓` | Select a known config |
| Enter / `l` / `a` / Space | Load selected (re-reads file when path is set) → **dashboard** |
| `d` then `y` | **Remove from list** (and index) — **does not delete the file on disk** |
| Esc / `q` | Close Config |

**List display:** name, WECO/lines/styles chips, and a **Path** column. A **`!`**
next to the name means the path is remembered but the file is currently missing.

**Explorer tips:** ↑↓ navigate; Enter opens a folder or chooses a file; Tab
focuses the filename field on Save As; Esc cancels. Overwrite of an existing
file asks for `y` confirm.

**What a config includes:** line visibility, line styles, visual prefs, WECO
enable map. **Not** series values, not USL/Target/LSL numbers, not viewport.

**WECO on load:** applies to the **active chart** and to session defaults for
**new** charts — not every chart already in the library.

**Same keys, different modes (easy to mix up):**

| Key | Dashboard | Config | Library |
|-----|-----------|--------|---------|
| `s` | Clear **specs** | **Save As** (explorer) | — |
| `S` | — | **Quick Save** known path | — |
| `w` / `W` | — | Graph **config** Save As / Load (explorer) | Whole **session** JSON |
| `p` / `P` | Pause (`p`) | Typed path save / load fallback | — |
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
| `k` / `K` | Keymap (**always**, including while PARAMS focused) |
| `+` / `A` | **Add Chart** wizard (param or analysis) |
| `;` | Toggle Side Stats **PARAMS** focus (when catalog non-empty) |
| `q` / Esc | **Quit** (dashboard only; Esc first clears PARAMS focus / open modals) |

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

## Tool parameter demo (`:fake_tool`)

**Default runners stay on `:triple`.** Prefer that for general exploration and tests. For a fab-style **one tool + parameter list + single primary chart** walkthrough:

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:fake_tool)'
# or
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench(seed_demos=:fake_tool, paused=true)'
```

What you get:

| Piece | Content |
|-------|---------|
| Tool | **Film-PTPECVD01** (synthetic; not loaded from `template_tool.csv`) |
| Params | Catalog of process parameters (e.g. Thickness 1.3µm, Refractive Index, HSQ Thickness) |
| Charts | **One** chart for the first parameter; `dashboard_max_panes = 1` |
| SharedTable | Long-format rows with a **Parameter** column (stable param ids) |
| Side Stats | **`▸ PARAMS`** + tool chip `◆ Film-PTPECVD01` |

Suggested keys:

1. **`;`** — focus PARAMS · **`j`/`J`** or **`↑`/`↓`** — move selection  
2. Select a param without a chart → status suggests **`+`**  
3. **`+`** → Param mode → pick another parameter → Enter → second pane (budget auto-bumps)  
4. **`+`** → Tab to **Analysis** → pick X̄-R / X̄-S / I-MR → Enter  
5. **`p`** still pauses; **`k`** still opens the keymap

---

## Suggested workflows

### A. Explore the demo (default triple)

1. `spc_workbench_demo()` — three charts, multi-pane  
2. `[` `]` · `1`–`8` · mouse hover · `?`

### A2. Explore tool + parameters (fake_tool)

1. `spc_workbench_demo(seed_demos=:fake_tool)`  
2. `;` · `j`/`J` · `+` add param/analysis chart · `p` pause · `k` keymap  

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
| `p` navigates params | No — **`p`/`P` always pause**. Params use **`;`** focus + **`j`/`J`** / **`↑`/`↓`**. |
| `k` is blocked while PARAMS focused | No — **`k`/`K` always open keymap**. |
| Default launch is single-chart tool demo | No — default is still **`seed_demos = :triple`**. Use **`:fake_tool`** explicitly. |
| Dashboard `a` opens Add Chart wizard | No — dashboard uses **`+` / `A`**. Library **`a`** is blank add. |
| Selecting a param rebuilds series | No — activates matching chart or Message only; never rematerializes on select. |
| All Side Stats sections are interactive | No — only **`▸ PARAMS`** is interactive; STATS/HOVER/LINES/WECO/CHARTS stay paint-only. |
| `q` in a path prompt quits | No — it types the letter `q`. Esc cancels. |
| Edit table → chart updates | No — rematerialize with builder **`a`** or table **`r`**. |
| Tools registry assigns charts | No — registry is the master list; builder sets `ch.tools`. |
| `d` always means table | No — dashboard `d` = table; **library** `d` = delete chart; **Config Saved** `d` = remove config from **list** (file stays on disk). |
| Neighbor charts show MR dual | No — dual secondary is **active chart only**. |
| Three overlays `c`/`v`/`o` + presets `e` | **One Config page** with four sections; deep-link keys still work. |
| Dashboard `s` saves a config | No — dashboard `s` **clears specs**. Config **`s`/`w`** = **Save As** (file explorer). |
| Config `s` is name-only / `w` is typed path only | Stale — primary save/load is the **file explorer**; `p`/`P` are typed-path fallbacks. |
| Library `w` vs Config `w` | Library = whole **session** (charts + data). Config = **graph config** file only. |
| Delete on Saved removes the JSON file | No — only the **list/index entry**. The file remains until you delete it outside the app. |
| Load config rewrites all charts’ WECO | No — **active chart** + session defaults for new charts only. |
