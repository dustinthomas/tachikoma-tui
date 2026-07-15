# TachikomaTUI — Application Functionality Walkthrough

> **Status:** Rough first-pass documentation (2026-07).  
> For authoritative keys, CSV/JSON contracts, and locks, prefer `docs/src/spc-workbench.md` and the repository `README.md`.  
> **Operators:** start with [`docs/user/`](user/README.md).  
> **In flux / planned:** see [`docs/ROADMAP.md`](ROADMAP.md).

This package is a **Julia terminal UI** built on **[Tachikoma.jl](https://kahliburke.github.io/Tachikoma.jl/dev/)** (Elm-style: model → `update!` → `view`). It ships **three apps**, from a tiny starter to a full SPC workbench.

Always launch Julia with:

```bash
julia --project=.
```

---

## In flux (read this first)

Large product work is still expected. This walkthrough describes **current** behavior; do not treat every key or layout detail as frozen.

| Treat as relatively stable | Likely to change |
|----------------------------|------------------|
| Live = **`g`/`G` only** (`L` = LSL) | Dashboard layout / dual-pane height policy polish |
| Default **`seed_demos = :triple`** (keep; use `:fake_tool` opt-in) | Help/keymap copy and secondary chrome |
| **`p`/`P` pause**, **`k`/`K` keymap** (not remapped for PARAMS) | PARAMS/add-chart polish strings |
| JSON schema **v1** additive contracts | Builder/table UX details |
| CSV series-first (`Value` / single col) | Attribute-chart operator workflows |
| Explicit materialize (not auto on load) | Key bindings if new modes are added |
| No Excel; classic `spc.jl` untouched | Size binning and other backlog features |

**When docs drift:** trust `src/` + `docs/src/spc-workbench.md` + `docs/ROADMAP.md` over older `design-spc-*.md` prose.

Full roadmap tables: **[docs/ROADMAP.md](ROADMAP.md)**.

---

## Big picture

| App | Entry point | What it is |
|-----|-------------|------------|
| **Hello** | `hello_tachikoma()` | Minimal counter demo |
| **Classic SPC chart** | `spc_demo()` / `static_spc_demo()` | Single interactive control chart |
| **SPC Workbench** | `spc_workbench()` / `spc_workbench_demo()` | Multi-chart WECO / capability workbench |

All follow the same Tachikoma pattern: a `Model`, keyboard/mouse events, and a terminal `view`.

---

## 1. Hello Tachikoma (starter)

**Run:**

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
```

**What you get:** A centered counter with help text.

| Key | Action |
|-----|--------|
| `space` / `+` / `↑` | +1 |
| `r` | Reset to 0 |
| `q` / Esc | Quit |

This exists mainly to prove Tachikoma wiring and the agentic test workflow. The real product surface is the SPC apps.

**Source:** `src/hello.jl`

---

## 2. Classic SPC chart

**Run:**

```bash
# Static (good for smoke tests)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.static_spc_demo()'

# Live + mouse
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_demo()'
```

### What it does

1. **Seeded process data** (~80 points, mean ~100, intentional out-of-control spikes).
2. Computes **mean, SD, UCL/LCL** and flags **violations**.
3. Renders a **canvas chart**: series line, dashed limits, ● / ◆ markers, crosshair.
4. **Side panel** with stats/legend + **arc gauges**.
5. Optional **live mode**: new points append on ticks until a cap (~200).

### Interaction

| Input | Behavior |
|-------|----------|
| `p` | Pause / resume live append |
| `r` / `z` | Reset viewport to full data |
| `←` `→` | Pan |
| Mouse hover | Tooltip + crosshair |
| Click-release | Snap vertical ┃ to nearest point |
| Drag | Pan |
| Wheel | Zoom |
| `q` / Esc | Quit |

Think of this as a **single-series SPC explorer** — a polished demo of charts + mouse in the terminal, not the multi-chart product.

**Source:** `src/spc.jl`

---

## 3. SPC Workbench (main app)

This is the primary application: a **multi-chart Statistical Process Control workbench** with WECO rules, capability (Cpk), specs, tools, CSV/JSON I/O, and an optional dual secondary canvas (MR / R / s).

**Run:**

```bash
# Seeded 3-chart dashboard (paused — best first look; default seed_demos=:triple)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'

# Single-chart tool + parameter demo (Film-PTPECVD01; opt-in — do not flip default)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:fake_tool)'

# Interactive (live ticks unless paused)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench(paused=true)'

# Load a saved session
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench(workbench="session.json")'
```

By default it seeds **three demo charts** (Primary / Secondary / Tertiary). That default (`seed_demos = :triple` on the model and both runners) is intentional — **keep it**. Use **`seed_demos = :fake_tool`** explicitly for the product single-chart + Side Stats PARAMS walkthrough. Do not flip the runner/model default without an explicit product decision and suite plan.

| `seed_demos` | Charts | Tools / params | `dashboard_max_panes` (seed sets) |
|--------------|--------|----------------|-----------------------------------|
| **`:triple`** (default) | 3 demos (Primary / Secondary / Tertiary) | empty tools, empty params | **3** |
| **`:fake_tool`** | 1 chart for first param | Film-PTPECVD01 + param catalog + long table | **1** |
| `:single` | 1 chart | empty | **1** |
| `:none` | 1 empty Primary (no random series) | empty | **1** |

`dashboard_max_panes` is **seed-coupled** (field default 3 for triple compat; `_ensure_charts!` overwrites when bootstrapping empty charts). Wizard add-chart paths can auto-bump the budget up to 3.

**Sources:** `src/spc_workbench.jl`, `src/spc_workbench_io.jl`  
**Detailed contracts:** `docs/src/spc-workbench.md` · **Operator guide:** `docs/user/workbench.md`

### Mental model

```text
SPCWorkbenchModel
├── charts[]              # ChartSpec list (name, type, values, limits, WECO, viewport…)
├── active                # which chart is focused
├── tools[]               # master tool registry (ids + descriptions)
├── params[]              # ParamEntry catalog (empty under :triple; filled by :fake_tool)
├── selected_param        # 1-based index into params; 0 when empty
├── dashboard_max_panes   # pane budget 1..3 (seed-coupled; JSON round-trips)
├── table                 # SharedTable (in-memory rows/cols from CSV/session)
├── filters               # owner / tool filters → which charts are visible
├── view_mode             # dashboard | library | builder | tools | table | help…
└── prefs                 # chart lines, visual prefs, WECO defaults for new charts
```

Each **chart** can be:

| Chart type | Use |
|------------|-----|
| **I-MR** | Individuals + Moving Range (default demo style) |
| **X̄-R** / **X̄-S** | Subgroup mean + range/std |
| **p / np / c / u** | Attribute charts |

Data comes from either:

- **Series** — a `values` vector (seeded, live, or CSV series import), or
- **Table** — columns mapped in the **builder**, then **materialized** into series.

Rendering goes through a **central render context**: control limits/zones, WECO markers, OOS vs specs, Cpk band/color, secondary series for dual canvas.

---

### Dashboard (default screen)

What you see:

- **Chart pane area** — up to `effective_dashboard_max_panes` (1…3) visible charts after filters
- **Active chart** can show **dual canvas**: primary on top, MR/R/s secondary below
- **Side Stats**: STATS → **PARAMS** (when catalog non-empty) → HOVER → LINES → WECO → CHARTS
- Status line / `last_event` feedback

**Core keys:**

| Key | Action |
|-----|--------|
| `[` `]` | Switch active chart |
| `←` `→` | Pan viewport (still pan when PARAMS focused) |
| `r` / `z` | Reset viewport + auto-fit Y |
| `p` / `P` | Pause **session** live ticks (**unchanged**; not param nav) |
| **`g` / `G`** | Toggle **active chart** live append (**not** `L`) |
| `u` / `t` / `l` | Edit USL / Target / **LSL** |
| `s` | Clear all spec limits |
| `1`…`8` | Toggle WECO rule N (**when PARAMS unfocused**) |
| `c` / `v` / `o` | Open **Config** → Rules / Lines / Visual |
| **`e`** | Open **Config** → **Saved** (known disk configs + file explorer) |
| `m` | Chart **library** |
| `b` | Chart **builder** |
| `x` | **Tools** registry |
| `d` | **SharedTable** grid |
| `f` | Filter prompt / clear filters |
| `?` / `h` | Help / keys chrome |
| `k` / `K` | Keymap (**always**, even when PARAMS focused) |
| **`+` / `A`** | Open **Add Chart** modal (param or analysis wizard) |
| **`;`** | Toggle Side Stats **PARAMS** focus (catalog non-empty only) |
| `q` / Esc | Quit (**only** from dashboard; Esc clears PARAMS focus / modals first) |

**PARAMS focus keys** (only while `side_focus === :params`):

| Key | Action |
|-----|--------|
| `j` / `J` | Next / previous parameter |
| `↑` / `↓` | Previous / next parameter |
| `1`…`9` | Jump to parameter index (absorbs digits; no WECO toggle) |
| Esc | Unfocus PARAMS (not quit) |

Selecting a param activates the chart with matching `ch.param == ParamEntry.id`, or Message `"no chart for param — press + to add"` — **never rematerializes** on select.

**Add Chart modal** (`+`/`A` on dashboard; library `a` stays blank add):

| Key | Action |
|-----|--------|
| Tab | Mode Param ↔ Analysis |
| `↑` `↓` | List cursor |
| Enter / Space | Confirm |
| Esc / `q` | Cancel (never quit) |

- **Param mode:** new chart for a catalog parameter (materialize from SharedTable when present).
- **Analysis mode:** same param id as active chart, different type — v1: I-MR / X̄-R / X̄-S only.
- Successful wizard add may auto-bump `dashboard_max_panes` to `min(3, visible count)`.

**Important lock:** live is only `g`/`G`. **`L` is LSL edit.** **`p` stays pause; `k` stays keymap.**

**Mouse on primary plot:** hover, pan, zoom, select — same spirit as classic SPC. Secondary canvas is display-only.

---

### Modes (overlays / full pages)

Modes are separate `view_mode`s. **Esc/`q` usually leave the mode** without quitting (except dashboard).

#### Chart library (`m`)

Manage the chart list:

- Navigate, activate chart (Enter)
- Add / clone / rename / delete (delete needs confirm; last chart can’t be deleted)
- **`i`** import CSV → series into a chart
- **`e`** export selected chart’s series as CSV
- **`w` / `W`** save / load **JSON session** (schema v1)

After a successful CSV import on a chart: that chart’s `live_enabled = false`, model is paused, viewport refit, limits recompute on next render.

#### Chart builder (`b`)

Keyboard form for the **active** chart:

- Name, chart type, column maps (`Value`, `n`, Tool, Time, Lot)
- Tools (csv list of tool ids), owner, subgroup size (2–25)
- Limits mode auto/manual + manual CL/UCL/LCL
- **`a`** apply + **materialize** from SharedTable when the table has data
- **`y`** cycle chart type

Materialize is **explicit** — editing the table alone does not auto-rebuild series.

#### Tools registry (`x`)

Master list of tools (`id` + description). Used for session filtering.

- Assign tools **to a chart** in the **builder** (`Tools (csv)`), not just by adding them here.
- Enter on a tool can set `filter_tool` and return to dashboard.

#### SharedTable grid (`d` from dashboard)

Spreadsheet-like view of the in-memory table:

- Move cursor, edit cells, page rows
- **`r`** rematerialize active chart from table
- No live/mouse while in this mode

CSV import can fill this table; multi-column CSVs keep extra columns for builder mapping.

#### Help / keymap

- `?`/`h` help, `k` keymap

#### Config (full page — `view_mode = :config`)

One surface for WECO rules, chart lines, visual prefs, and saved configs.
Replaces the old three-tab plot overlay and the separate Graph Presets page.

- Deep-links from dashboard: **`c`** Rules · **`v`** Lines · **`o`** Visual · **`e`** Saved
- Reach Saved also via **`v`** then Tab/`e`, or **`e`** directly
- In-Config: Tab cycles sections; `c`/`v`/`o`/`e` jump (do not close); **Esc/`q` only** close → dashboard
- Toggles apply immediately on the live model
- **Saved (disk-first):** list of known graph-config files (session list + durable index)
  - **`s` / `w`** → **Save As** (in-TUI file explorer)
  - **`S`** → **Quick Save** to known path (or Save As if none)
  - **`W`** → **Load** via file explorer → apply → dashboard
  - **`p` / `P`** → typed path save/load fallback (secondary)
  - Enter / `l` / `a` / Space → load selected (re-reads path when set) → dashboard
  - **`d` then `y`** → remove from list+index only (**file kept on disk**)
  - Path column + **`!`** missing-file badge when the remembered path is gone
- Load applies WECO to the **active chart** + session defaults for new charts (not every chart)
- Config is **not** full session save (library `w`/`W` is session JSON; Config graph-config I/O is explorer / `p`/`P`)

---

### SPC analytics (what the charts compute)

Under the hood (also exported for library use):

| Piece | Role |
|-------|------|
| **`compute_limits_and_zones`** | CL, UCL/LCL, ±1/2/3σ zones |
| **`weco_detect`** | Western Electric / WECO run rules (toggleable 1–8) |
| **`compute_capability`** | Cp/Cpk-style capability from specs + process σ |
| **`detect_oos`** | Out-of-spec vs USL/LSL (distinct from control-limit OOC) |
| **Secondary series** | MR, R, or s with its own limits for dual canvas |
| **Y auto-fit** | Viewport Y so points + limits stay on-screen |

Demo data is seeded (deterministic RNG) so tests and demos stay stable.

---

### Data in / data out

| Path | Format | Notes |
|------|--------|-------|
| **CSV import** | Series-first: prefer `Value` column (or single column) | Simple parser; max 50k rows; fail closed |
| **CSV export** | `Value` + floats | Library-selected or active chart |
| **JSON session** | Schema **v1** | charts, active, tools, table, prefs, WECO defaults, optional `graph_presets` (+ paths) |
| **Graph config file** | `kind=graph_preset` JSON | Lines/styles/visual/WECO only; Config explorer Save As / Load |
| **HTML archive** | Extract state from archived HTML mockup | `load_html_archive` family |

JSON is fail-closed: bad version / empty charts / bad table → error, model unchanged on in-place load. No passwords/admins. Load does **not** auto-rematerialize from table.

Sample fixtures: `test/fixtures/spc/sample_value.csv` and header templates under `test/fixtures/spc/templates/`.

Full CSV/JSON field tables: **`docs/src/spc-workbench.md`**.

---

## Typical user flows

### 1. Explore the demo

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'
```

Switch charts with `[` `]`, pan, toggle WECO with `1`–`8`, open help with `?`.

### 1b. Tool + parameters (fake_tool)

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:fake_tool)'
```

Single pane for Film-PTPECVD01 / first parameter. `;` focus PARAMS, `j`/`J` navigate, `+` add another param or analysis chart. Keep default `:triple` for general demos and CI.

### 2. Import your series

1. `m` → library → `i` → path to CSV with a `Value` column
2. Chart becomes static (live off); inspect with mouse/pan; export with `e` if needed.

### 3. Multi-column / subgroups

1. Import multi-column CSV (fills SharedTable)
2. `b` builder: set chart type, `col_value` / `col_lot` / tools, Apply (`a`)
3. Or edit cells in `d` table mode, then rematerialize with `r`

### 4. Persist a session

1. Library `w` → save `session.json`
2. Later: `spc_workbench(workbench="session.json")` or library `W` load

### 5. Live monitoring

1. `spc_workbench()` without pause
2. Per chart: `g` to enable/disable live append
3. `p` pauses all ticks for the session

---

## How the pieces relate

```text
hello.jl              minimal Elm demo
spc.jl                single-chart interactive SPC
spc_workbench.jl      multi-chart product (UI + analytics + modes)
spc_workbench_io.jl   CSV + JSON (+ HTML state) I/O
TachikomaTUI.jl       package entry + exports
```

| Layer | Role |
|-------|------|
| **Classic SPC** | One polished chart |
| **Workbench** | Small SPC “IDE” in the terminal: library, builder, tools, table, specs, WECO, capability, session files |

---

## Architecture notes

- **Tachikoma Elm loop**: `update!(model, KeyEvent|MouseEvent)` mutates state; `view(model, Frame)` draws each frame; ticks drive live append when not paused.
- **UI tests** use `Tachikoma.TestBackend` (no real TTY): inject keys, re-render, assert text/geometry.
- **Full suite:** `julia --project=. test/runtests.jl`
- **Documenter pages:** `docs/src/index.md`, `docs/src/spc-workbench.md`, `docs/src/api.md`

### Product locks (do not “fix” casually)

| Topic | Rule |
|-------|------|
| Live toggle | **`g` / `G` only** — never `L` (`L` is LSL edit) |
| Seed demos | Default **`seed_demos = :triple`** on model + runners — **keep**; use `:fake_tool` opt-in only |
| Pause / keymap | **`p`/`P` pause**, **`k`/`K` keymap** — not remapped for PARAMS focus |
| Excel | **Out of scope** — CSV + JSON only long-term |
| I/O tests | `using TachikomaTUI` only — do not raw-include I/O modules |

---

## Related docs

| Path | Contents |
|------|----------|
| [`docs/user/`](user/README.md) | Rough **operator** guides (getting started, workbench, I/O) |
| [`docs/ROADMAP.md`](ROADMAP.md) | Shipped vs in flux vs backlog / non-goals |
| `README.md` | Quick start, runners, verification gates |
| `docs/src/index.md` | Documenter home |
| `docs/src/spc-workbench.md` | Keys, CSV format, JSON schema v1 |
| `docs/src/api.md` | Public API via Documenter `@autodocs` |
| `design-spc-*.md` (repo root) | Historical design / PR plans (may lag master) |
| `AGENTS.md` | Agentic workflow and Julia/Tachikoma rules |
| `CONTRIBUTING.md` | Contribution notes |
