# SPC Workbench

Multi-chart WECO / capability workbench: interactive I-MR explorer with chart
library metadata, live append gates, and JSON session persistence (schema v1).
CSV series import/export land with the I/O feature PRs; formats below are the
locked contracts.

## Runners

```julia
using TachikomaTUI

# Seeded triple-demo dashboard (static / gate-friendly) — default seed_demos=:triple
spc_workbench_demo()

# Opt-in single-chart tool + parameter demo (Film-PTPECVD01)
spc_workbench_demo(; seed_demos = :fake_tool)

# Interactive; optional pause and schema-v1 load
spc_workbench(; paused = true)
spc_workbench(; seed_demos = :fake_tool, paused = true)
spc_workbench(workbench = "session.json")
```

`seed_demos` defaults to **`:triple`** (Primary / Secondary / Tertiary) on the
model and both runners. Do **not** change that default. Use `:fake_tool`,
`:single`, or `:none` only in explicit constructs / product walkthroughs.

| `seed_demos` | Bootstrap | `dashboard_max_panes` set by `_ensure_charts!` |
|--------------|-----------|-----------------------------------------------|
| **`:triple`** (default) | 3 demo charts; empty tools; empty params | **3** |
| **`:fake_tool`** | Film-PTPECVD01 tool, param catalog (≥3), long SharedTable, **1** chart for `params[1]` | **1** |
| `:single` | 1 demo chart | **1** |
| `:none` | no charts until user/load | **1** |

**Seed-coupled pane budget:** model field default `dashboard_max_panes = 3`
(triple-compat). When `_ensure_charts!` bootstraps an empty chart list it calls
`_seed_dashboard_max_panes!` (`:triple` → 3, else 1). Non-empty charts (e.g.
JSON load) do **not** re-seed the budget. Wizard `add_param_chart!` /
`add_analysis_chart!` may auto-bump to `min(3, length(visible_charts))`.
View uses `k = effective_dashboard_max_panes(m)` (clamped 1…3).

`:fake_tool` data is **synthetic** (`default_fake_tools`,
`default_fake_tool_params`, `build_fake_tool_table`) — not loaded from
`test/fixtures/spc/templates/template_tool.csv`.

## Keys

### Dashboard (always available)

| Key | Action |
|-----|--------|
| `q` / Esc | Quit (dashboard only). Esc first clears PARAMS focus or open modals. |
| `p` / `P` | Pause / resume live tick (**unchanged**; not param navigation) |
| **`g` / `G`** | Toggle active chart `live_enabled` (**not `L`**) |
| `r` / `z` | Reset viewport (full range + auto Y) |
| `c` / `C` | Open **Config** → Rules (WECO) |
| `v` / `V` | Open **Config** → Lines (visibility + style) |
| `o` / `O` | Open **Config** → Visual preferences |
| **`e` / `E`** | Open **Config** → **Saved** (disk-first known configs + file explorer) |
| `u` / `t` / `l` | Edit USL / Target / **LSL** (`L` is LSL, not live) |
| `s` | Clear all **spec** limits (USL/Target/LSL) on active chart |
| `1`…`8` | Toggle WECO rule N on active chart when **PARAMS unfocused** |
| `[` `]` | Switch active chart |
| `←` `→` | Pan viewport (still pan when PARAMS focused) |
| `m` / `M` | Open chart library |
| `x` / `X` | Open tools registry |
| `f` / `F` | Cycle filter prompt / clear filters |
| `b` / `B` | Open chart builder |
| `?` / `h` | Help / keys chrome |
| `k` / `K` | Keymap page (**always**, even when `side_focus === :params`) |
| **`d` / `D`** | Open SharedTable grid (`view_mode=:table`) |
| **`+` / `A`** | Open **Add Chart** modal (dashboard only; library keeps `a` = blank add) |
| **`;`** | Toggle Side Stats **PARAMS** focus (`side_focus` `:none` ⇄ `:params`; no-op if catalog empty) |

### Side Stats ▸ PARAMS (interactive when catalog non-empty)

Paint order: **STATS → PARAMS → HOVER → LINES → WECO → CHARTS**. Only PARAMS is
interactive; other sections remain read-only. Under height pressure PARAMS drops
content before starving WECO bubbles (`reserve_tail`).

| Key | When | Action |
|-----|------|--------|
| `;` | catalog non-empty | Toggle params focus |
| `j` / `J` | focused | Next / previous parameter (`select_param!`) |
| `↑` / `↓` | focused | Previous / next parameter |
| `1`…`9` | focused | Jump to index (absorbs digit; **no** WECO toggle) |
| Esc | focused | Clear focus (`params unfocused`); does not quit |

`select_param!(m, idx)`: set `selected_param`; find chart with
`c.param == params[idx].id` → `set_active_chart!`; else Message
`"no chart for param — press + to add"`. **Never rematerialize** on select.
Empty catalog ⇒ `selected_param = 0`.

### Add Chart modal (`add_chart_open`)

Full key absorb while open (KD-DC-17). Esc/`q` close modal only — **never quit**.

| Key | Action |
|-----|--------|
| Tab | Toggle mode `:param` ⇄ `:analysis` |
| `↑` / `↓` | Move list cursor |
| Enter / Space | Confirm (`add_param_chart!` or `add_analysis_chart!`) |
| Esc / `q` / `Q` | Cancel |

| Mode | Behavior |
|------|----------|
| **Param** | Chart for selected catalog `ParamEntry`; materialize from SharedTable when rows exist; refuse duplicate `(param id, chart_type)` |
| **Analysis** | Clone from **active** chart: same `param` id / tools / specs / column maps; type from v1 list **I-MR, X̄-R, X̄-S** only; refuse attributes / duplicates |

Successful wizard adds auto-bump `dashboard_max_panes` when visible charts exceed
the budget (wizard paths only — not blank library `add_chart!`).

### Config (`view_mode = :config`)

**One full-page Config surface** for WECO rules, chart lines, visual prefs, and
saved configs. Replaces the old three-tab plot overlay (`config_open`) and the
separate Graph Presets page (`view_mode = :presets`).

| Section | Open from dashboard | In-Config jump |
|---------|---------------------|----------------|
| **Rules** | `c` / `C` | `c` / `C` |
| **Lines** | `v` / `V` | `v` / `V` |
| **Visual** | `o` / `O` | `o` / `O` |
| **Saved** | `e` / `E` | `e` / `E` |

| Key | Action |
|-----|--------|
| Esc / `q` | Close → dashboard (**only** close keys; does not quit) |
| Tab | Cycle Rules → Lines → Visual → Saved → Rules |
| `c` / `v` / `o` / `e` | Jump section (stay on Config; **not** close) |
| `↑` / `↓` | Move selection within section |
| Space / Enter | Rules/Lines/Visual: toggle item. **Saved:** load selected → dashboard |
| `1`…`N` | Jump + toggle (Rules N≤8, Lines N≤5, Visual N≤4) |
| `←` / `→` | **Lines only:** cycle line style (`solid` / `dotted` / `dashed` / `long_dash`) |

**Live apply:** toggles mutate the model immediately (no separate Apply). List
or file **load** is the batch apply path.

#### How to open Saved

```text
Dashboard ──v──► Config [Lines]
                 Tab / e ──► Config [Saved]
Dashboard ──e──► Config [Saved]   (direct deep-link)
```

#### Saved section (disk-first list + in-TUI file explorer)

The Saved list is a **library of known graph-config files** (path + name +
summary/body), merged with a durable **config index** under the XDG data dir
(`…/tachikoma-tui/graph_config_index.json`). Disk is the source of truth for
path-bearing rows: loading re-reads the JSON file (fail-closed).

| Key | Scope | Action |
|-----|-------|--------|
| **`s` / `w`** | Any Config tab | **Save As** — open in-TUI **file explorer** (pick dir + filename) |
| **`S`** | Any Config tab | **Quick Save** — write to selected entry path or `last_graph_config_path` without overwrite confirm; if no known path → Save As explorer |
| **`W`** | Any Config tab | **Load** — open file explorer to pick a `.json` graph config |
| **`p`** | Any Config tab | Typed-path **save** fallback (Message path prompt; secondary) |
| **`P`** | Any Config tab | Typed-path **load** fallback (Message path prompt; secondary) |
| `↑` / `↓` | Saved only | Select a known config |
| Enter / `l` / `a` / **Space** | Saved only | **Load** selected → re-read path (if set) → apply → **dashboard** (R2) |
| `d` then `y` | Saved only | **Remove from list + index** — does **not** delete the file on disk |

**Save As / Load explorer (primary I/O):**

- Modal over Config (not a separate `view_mode`). Shows directories + `*.json`.
- Navigate with ↑↓ / PgUp/PgDn; Enter opens a directory or commits a file.
- Tab toggles list ⇄ filename focus (Save As). Esc cancels (never quits).
- `h` toggles hidden entries; `~` jumps to home.
- Save As rejects empty / `.` / `..` / path separators in the filename; appends
  `.json` when missing. Overwriting an existing file asks `y` confirm first
  (explorer closes, then Message confirm).
- Successful save always upserts the Saved list + index, selects the entry, and
  sets `last_graph_config_path`. Stay on Config.
- Successful load applies and returns to the **dashboard** (R2).

**Typed path (`p` / `P`):** escape hatch for paste/automation. Prefills
`last_graph_config_path` only — never a silent default write. Not the primary
chrome (explorer is).

**List chrome:** column header `Name · WECO · Lines · Styles · Path`. Path is
elided (`~/…` when under home). A **`!`** badge on the name means the path is
set but the file is currently missing (cached on open/merge — not re-stat every
frame). Chips come from the loaded body, or from the index summary when the
body is still lazy. No mtime column.

**Delete:** `d`+`y` drops the entry from the session list and the durable index.
The JSON file on disk is **kept**. `last_event` still contains `"deleted preset"`.

**R2 load:** applying a list or file config returns to the dashboard (not stay
on Config). Empty list: `last_event` ≈ `"no presets to load"`; stay on Saved.
Path-bearing list load finalizes `"loaded graph config <path>"`. Path-less
**legacy** session rows (no path) still apply from memory as
`"preset applied: <name>"`. File save success: `"saved graph config <path>"`.

**WECO apply scope (KD-UC-5):** load applies WECO enable map to the **active
chart** and session `default_rules` (seeds new charts). It does **not** rewrite
other charts’ `enabled_rules`, series values, spec numbers, or viewport.

**Included in a config** (lines + styles + visual + WECO). **Not** included:
series data, USL/Target/LSL values, tools, table, viewport.

Fail-closed on bad/empty path or bad JSON: no partial apply; list unchanged on
load fail.

#### Same glyph, different mode (mode-gated)

| Glyph | Dashboard | Config | Library |
|-------|-----------|--------|---------|
| `c` | Open Config → Rules | Jump → Rules | Clone chart |
| `s` | Clear **spec** limits | **Save As** (file explorer) | — |
| `S` | — | **Quick Save** known path | — |
| `e` | Open Config → Saved | Jump → Saved | Export CSV |
| `w` | — | **Save As** (alias of `s`) | Save workbench **session** |
| `W` | — | **Load** graph config (explorer) | Load workbench **session** |
| `p` / `P` | Pause (always; not param nav) | Typed path save / load fallback | — |
| `a` / `A` | **`A`** = Add Chart modal; **`a`** unbound | — | Blank `add_chart!` |
| `+` | Add Chart modal | — | — |
| `;` | PARAMS focus toggle | — | — |
| `d` | SharedTable grid | Remove config from list (Saved; file kept) | Delete chart |
| `l` | Edit LSL | Load selected config | — |
| `1`–`8` | WECO when unfocused; param jump 1–9 when PARAMS focused | Jump+toggle in Rules (or Lines/Visual range) | — |

Config is **not** full session save. Library `w`/`W` persist charts + series +
tools + table + current graph fields; Config `s`/`w`/`S`/`W` write/read a
single graph-config file only (explorer primary; `p`/`P` typed fallback).

### Dual secondary canvas (active plot)

I-MR / X̄-R / X̄-S charts can show a **secondary series canvas** (MR / R / s) stacked
under the **active** plot only (neighbors stay single-series when drawn).

| Item | Behavior |
|------|----------|
| Pref | Config → Visual (`o`) → **Secondary canvas (MR/R/s)** (default **on**) |
| Limits | Secondary CL/UCL/LCL only (no WECO markers, no USL/LSL, no ±σ zones on secondary) |
| Mouse | Primary only — secondary is display-only; `plot_area` / `viewport` stay primary |
| Height | If multi-pane would starve dual (active outer &lt; 14), **temporary single-pane compress** for that frame so dual can fit; not permanent focused mode. Pref off restores neighbor panes. |

### Builder mode (`b` / `B`)

Keyboard form for the **active** chart. Esc/`q`/`b` close to dashboard (never quit).

| Key | Action |
|-----|--------|
| `↑` `↓` | Move field selection |
| Enter / Space | Edit string field, or toggle `limits_mode` / cycle `chart_type` |
| `a` / `A` | Apply + materialize from in-memory SharedTable (when non-empty) |
| `1`…`8` | Toggle WECO rule N on the chart |
| `y` / `Y` | Cycle **chart type only** (I-MR → Xbar-R → …) |

**Fields (order):** Name, Chart type, Value col, N col, Tool col, Time col, Lot col,
Tools (csv), Owner, Subgroup n, Limits mode, Manual CL / UCL / LCL.

| Field | Notes |
|-------|--------|
| `col_lot` | X̄ group column; with Xbar-R/S + non-empty lot → table-subgroup materialize |
| `col_n` | Sample-size column map (attribute charts) |
| `col_time` | Timestamp / label column |
| `subgroup_size` | Integer clamped **2..25**; invalid edit keeps prior |
| `owner` | String; matches session `filter_owner` (strip equality) |

No size-binning fields yet. Table summary line shows row/col counts and chart `source`.

### Live toggle (`g` / `G`)

Per-chart only (no model-level live flag):

- Seeded demos start with `live_enabled = true`.
- Successful CSV import sets **that chart’s** `live_enabled = false` and
  `m.paused = true`.
- Dashboard **`g` / `G`** toggles `current_chart(m).live_enabled` with
  `last_event` feedback (`"live on"` / `"live off"`).
- **`L` is reserved for LSL edit** — never document or implement live as `L`.
- JSON always writes `live_enabled`; if omitted on load → `false` (safe default).

### Library mode (file + CRUD keys)

Library UI mode is entered from the dashboard (feature PR for `m` binding).
Canonical library keys:

| Key | Action |
|-----|--------|
| `↑` `↓` | Move `library_selected` |
| Enter | Activate selected chart → dashboard |
| `a` | Add empty chart |
| `c` | Clone selected (**library only**; dashboard `c` = config) |
| `d` then `y` | Delete (refuse if only one chart remains) |
| `n` | Rename prompt |
| **`i`** | Import CSV prompt |
| **`e`** | Export CSV of `library_selected` (export PR) |
| **`w` / `W`** | Save / load JSON session |
| Esc / `q` | Close library → dashboard (**do not quit**) |

**Mode-gate (KD-P2-20):** library `d` = delete chart; **dashboard** `d`/`D` =
SharedTable grid. Tools registry (when present) keeps mode-local `d` for tool
delete. Never open the grid from library/tools with `d`.

**Never** use `o` / `O` for open-file (those open Config → Visual on the
dashboard). Library file keys are `i` / `e` / `w` / `W` only. Config graph-config
files use the **file explorer** (`s`/`w` Save As, `W` Load) or typed `p`/`P`
fallback (see collision table under Config).

### Tools registry (`view_mode=:tools`)

Opened from the dashboard with **`x` / `X`**. This is the **master tool list**
(`m.tools::Vector{ToolEntry}` with `id` + `description`), persisted in JSON as
the session `tools` array.

| Key | Action |
|-----|--------|
| `↑` `↓` | Move `tools_selected` |
| `a` | Add tool (prompt id, then description) |
| `n` | Edit description of selected |
| `d` then `y` | Delete selected (confirm) |
| Enter | Set session `filter_tool` to selected id → dashboard |
| Esc / `q` | Close → dashboard (**do not quit**) |

**Registry vs chart tools (important):**

| Layer | Role |
|-------|------|
| `m.tools` (this page) | Master registry of canonical tool ids |
| `ch.tools` | Per-chart filter assignment — what `visible_charts` matches |
| Builder field `Tools (csv)` | **Primary assign path** for `ch.tools` |

CRUD on the registry alone does **not** put ids onto demo charts. Assign tools
to a chart via the builder (`b`), then dashboard `f` tool filter can match.

### SharedTable grid (`view_mode=:table`)

Inspect and lightly edit the in-memory SharedTable (not Excel). Open from the
**dashboard** with **`d` / `D`**.

| Key | Action |
|-----|--------|
| `↑` `↓` `←` `→` | Move cell cursor |
| PgUp / PgDn | Page rows |
| Enter | Edit selected cell (string buffer) |
| Enter (while editing) | Commit cell to `m.table.rows[r][col]` as `String` |
| Esc (while editing) | Cancel edit |
| **`r` / `R`** | **Explicit** rematerialize active chart from table |
| Esc / `q` | Close → dashboard (**do not quit**) |

- Empty table shows a warn message (import CSV via library `i`, or load session).
- Cell edits update SharedTable only; chart series change **only** after
  explicit rematerialize (`r` here, or builder apply). **No** auto-rematerialize
  on JSON/HTML load.
- Live tick and mouse are gated off while `view_mode=:table` (keyboard-first).
- Render caps at 50 columns with horizontal scroll; rows are windowed.

### Prompt behavior

While a path/name prompt is open (`prompt_kind !== nothing`):

- Characters and backspace edit `prompt_buf`; **`q` is a typed character**, not quit.
- Enter applies; Esc cancels.
- Fail closed: on import/load/save error, charts are not partially mutated;
  `last_event` gets a stable prefix (`"import err: …"`, `"load err: …"`,
  `"save err: …"`).

## CSV format (series-first)

Phase A policy — no column-picker UI, no XLSX.

### Ingress (import)

- **Header:** prefer a case-sensitive `Value` column; or a single-column file
  (header optional).
- **Delimiter:** comma. Parser is deliberately simple (no full RFC4180 quoted
  fields in P0).
- **Newlines:** `\n` / `\r\n`; strip UTF-8 BOM; skip empty lines.
- **Non-numeric cells:** warning; if ≥1 good float → success, else error kind
  `:all_invalid`.
- **Size guard:** `max_rows = 50_000` → `:too_large` when exceeded.

Fixture example (`test/fixtures/spc/sample_value.csv`):

```text
Value
100.1
99.8
100.4
```

### Sample CSV templates (headers only)

Branded **blank** CSV templates live under `test/fixtures/spc/templates/`.
Header row only — no Excel / XLSX, no generator UI (KD-P2-13). Copy a
template, fill rows, then import via library **`i`**.

| File | Purpose | Header |
|------|---------|--------|
| `template_generic.csv` | Generic multi-column fab sheet | `Timestamp,Tool,Lot,Wafer,Chip,Value,Defects,n` |
| `template_tool.csv` | Tool-aware columns (filter / `col_tool` map) | `Timestamp,Tool,Lot,Wafer,Value,Defects,n` |
| `template_size_bin.csv` | Size-bin oriented (one row per particle/defect) | `Timestamp,Tool,Lot,Wafer,Value,Units,Defects,n` |

Notes:

- Phase A import still prefers a case-sensitive **`Value`** column (series-first).
  Extra columns are kept on the in-memory SharedTable when multi-column CSV is
  ingested; map `col_tool` / `col_time` / `col_lot` in the builder as needed.
- **Size-bin template:** `Value` = numeric item size; `Wafer` = subgroup column
  for per-wafer counts when size binning is enabled (optional late feature).
  Leave `Defects` / `n` blank when binning supplies the count series.
- Paths relative to package root:

```text
test/fixtures/spc/templates/template_generic.csv
test/fixtures/spc/templates/template_tool.csv
test/fixtures/spc/templates/template_size_bin.csv
```

### After successful import into a chart

1. Replace (default) or append `ch.data.values`.
2. Full-range viewport + auto-fit Y when `n > 0`.
3. `ch.live_enabled = false` on that chart only.
4. `m.paused = true`.
5. Limits recompute via `resolve_chart_render_context` on next view.
6. `last_event = "imported N values from …"`.

### API (package load)

```julia
using TachikomaTUI  # I/O tests and callers must use the package, not raw include

# Planned / feature-PR surface (see spc_workbench_io.jl when present):
# parse_csv_table(path; value_col="Value", max_rows=50_000)
# import_csv_into_chart!(ch, path; value_col="Value", replace=true)
# import_csv_new_chart!(m, path; name=..., kwargs...)
# export_csv_series(path, values; col_name="Value")
```

Export writes a `Value` header plus one float per line (library-selected chart
when in library mode, else active chart).

## JSON session schema v1

Pure dict / file APIs (implemented):

```julia
using TachikomaTUI

d = workbench_to_dict(m)                 # Dict (schema v1)
m2 = workbench_from_dict(d)              # new model | error String
err = workbench_from_dict!(m, d)         # nothing | error String (fail closed)

save_workbench(m, "session.json")        # nothing | "save err: …"
m3 = load_workbench("session.json")      # model | "load err: …"
load_workbench!(m, "session.json")       # in-session replace (library W)
```

### Root object

| Field | Required | Notes |
|-------|----------|-------|
| `version` | **yes** | Must be integer `1` |
| `charts` | **yes** | Non-empty array of chart objects |
| `active` | **yes** | 1-based index (clamped on load) |
| `tools` | no | Array of `{id, description}` |
| `dashboard_max_panes` | no | Integer 1…3 (clamped). **Present** → honor; **absent** → heuristic from chart count (`n≥2` → multi). Always written on save. |
| `default_rules` | no | Session WECO enable map for **new** charts (`add_chart!` seed). Distinct from per-chart `enabled_rules`. Omitted → module `DEFAULT_WECO_RULES`. |
| `show_chart_lines` | no | CL / σ / specs visibility |
| `chart_line_styles` | no | Per-line style ids (`solid` / `dotted` / `dashed` / `long_dash`); omitted → defaults |
| `visual_prefs` | no | Series connectors + `secondary_canvas` (dual MR/R/s under active) |
| `graph_presets` | no | Array of graph configs (whole graph set); may include optional `path` for disk-first list; wire key stays `graph_presets`; **omitted on save when empty** |
| `paused` | no | Bool; default false if omitted |
| `table` | no | SharedTable `{columns, rows}`; **omitted on save when empty**; missing/null → empty on load |

**Note:** session JSON currently serializes tools, charts, table, and
`dashboard_max_panes`. The in-memory **param catalog** (`m.params` /
`selected_param`) is session/UI state seeded by `:fake_tool` (not a required
schema root key). Chart linkage uses per-chart `param` / optional
`col_param` + `param_filter` (stable **ParamEntry.id** strings).

### Graph config object (`graph_presets[]` + standalone files)

Snapshot of the **whole graph config set** (no series data): what is drawn,
line styles, visual prefs, and WECO rules to calculate. Product language: **config**;
session JSON key and Julia type remain `graph_presets` / `GraphPreset`.

UI: **Config → Saved** — disk-first list of known files + in-TUI explorer
(see [Config](#config-view_mode--config) keys). No separate presets page.

| Field | Required | Notes |
|-------|----------|-------|
| `name` | **yes** | Non-empty string (display / legacy path-less identity) |
| `path` | no | Absolute path on the **session / index list only**. Standalone files **never** embed host paths. Identity for path-keyed upsert when non-empty. |
| `show_chart_lines` | no | Bool map; defaults if omitted |
| `chart_line_styles` | no | Style map; unknown style string → fail-closed |
| `visual_prefs` | no | Bool map; defaults if omitted |
| `enabled_rules` | no | WECO map captured from active chart at save time |

#### Standalone graph-config file

Helpers: `save_graph_preset(p, path)` / `load_graph_preset(path)`. TUI wires
**file explorer** (`s`/`w` Save As, `W` Load) and typed fallbacks (`p`/`P`).

```json
{
  "kind": "graph_preset",
  "version": 1,
  "name": "fab-dense",
  "show_chart_lines": { "cl": true, "sigma1": true, "sigma2": true, "sigma3": true, "specs": false },
  "chart_line_styles": { "cl": "solid", "sigma1": "dotted", "sigma2": "dotted", "sigma3": "dotted", "specs": "dashed" },
  "visual_prefs": { "solid_series": true, "solid_stroke": true, "braille_series": false, "secondary_canvas": true },
  "enabled_rules": { "WECO-1": true, "WECO-2": true }
}
```

| Rule | Behavior |
|------|----------|
| Write `kind` | Always `"graph_preset"` |
| Load `kind` | Accepts `"graph_preset"` or alias `"graph_config"` |
| File-save `name` | Basename of path without extension (empty → `"default"`) |
| File-save list | Path-keyed upsert into session list + durable index; select entry; set `last_graph_config_path` |
| File-load upsert | Path-keyed upsert of **file payload**, apply → dashboard (`"loaded graph config <path>"`) |
| List load (path set) | Always **re-reads** the file (disk is source of truth); fail-closed if missing/bad |
| Delete from Saved | Removes list + index entry only; **never** `rm` the file |
| Fail-closed | Bad path / JSON / kind → `save err:` / `load err:`; model + list unchanged on load fail |
| Prefill | `last_graph_config_path` / selected path only; no silent default path write |

**Durable index:** known configs also live in
`$XDG_DATA_HOME/tachikoma-tui/graph_config_index.json` (or
`~/.local/share/tachikoma-tui/…`). Opening Saved merges index ↔ session list
(path is identity; MRU order; missing files get a `!` badge). Cap 50 entries.

**Apply scope:** session lines/styles/visual; **active-chart** WECO + session
`default_rules`. Not other charts’ rules, not series/specs/viewport.

### Per-chart object

| Field | Required | Notes |
|-------|----------|-------|
| `id` | **yes** | String |
| `name` | **yes** | String |
| `chart_type` | **yes** | Wire string: `I-MR`, `Xbar-R`, `Xbar-S`, `p`, `np`, `c`, `u` |
| `values` | **yes** | Array of numbers (may be empty) |
| `usl` / `target` / `lsl` | no | Number or null |
| `enabled_rules` | no | Per-chart WECO map (rule-id → bool). Not the session `default_rules`. |
| `param` / `units` / `owner` | no | Strings; `param` stores **ParamEntry.id** when linked (not display name) |
| `tools` | no | Array of tool id strings |
| `limits_mode` | no | `"auto"` (default) or `"manual"` |
| `manual_cl` / `manual_ucl` / `manual_lcl` | no | Number or null |
| `subgroup_size` | no | Integer (default 5) |
| `live_enabled` | no | Always written on save; **omitted → false** on load |
| `source` | no | `"series"` (default) or `"table"` provenance |
| `col_value` / `col_n` / `col_tool` / `col_time` | no | Column maps for table materialize |
| `col_lot` | no | Always written on save; **omitted → `""`** on load; X̄ group column |
| `col_param` | no | Parameter column name for table filter (fake_tool seed: `"Parameter"`); **omitted → `""`** |
| `param_filter` | no | When set with `col_param`, keep rows where cell equals this **stable id** (same string as `param`); **omitted → `""`** |
| `viewport` | no | `{x0, x1, ylo, yhi}`; bootstrapped if missing |

### SharedTable object (`table`)

| Field | Required | Notes |
|-------|----------|-------|
| `columns` | no | Array of strings (default `[]` if omitted) |
| `rows` | no | Array of row objects; each cell must be scalar (string / number / bool / null) |

- Cells are coerced to strings on load (`null` → `""`).
- Extra keys on a row (not listed in `columns`) are kept; missing column keys stay absent until materialize (`get(row, col, "")`).
- **Fail closed:** wrong `table` type, non-array columns/rows, non-object row, non-scalar cell, or more than **50 000** rows → whole session parse fails (model unchanged on in-place load).
- **No auto-rematerialize on load:** chart `values` remain display source of truth; call `materialize_chart_from_table!` (e.g. builder apply) to rebuild series from the restored table.

### Load semantics

- **Fail closed:** corrupt / unsupported version / empty charts / bad `table` → error string;
  in-place load does not mutate charts or table.
- **Never** deserialize `admins` / passcodes (ignored if present).
- Unknown chart / root keys ignored.
- `load_workbench!` replaces charts/active/tools/table/optional prefs; clears UI
  ephemerals (config/edit/hover/drag/prompt); preserves `rng`, `tick`, `quit`,
  geometry, `live_max`. Does **not** call `materialize_chart_from_table!`.
- Session `default_rules` round-trips independently of per-chart `enabled_rules`.
  After load, `add_chart!` seeds new charts from restored session defaults.
  Demo seed (`_ensure_charts!`) keeps explicit rules and does not rewrite from
  session defaults.
- Status: `"loaded …"`, `"saved …"`, or prefixed errors.

### Minimal example

```json
{
  "version": 1,
  "active": 1,
  "charts": [
    {
      "id": "CHT-1001",
      "name": "Primary",
      "chart_type": "I-MR",
      "values": [100.1, 99.8, 100.4],
      "live_enabled": false,
      "usl": null,
      "target": null,
      "lsl": null
    }
  ],
  "paused": true
}
```

## WECO / stats

Pure functions exported from `TachikomaTUI`:

- `weco_detect`, `compute_limits_and_zones`, `compute_capability`
- `detect_oos`, `cpk_band`, `resolve_chart_render_context`, …

Covered by `test/test_spc_workbench.jl`. UI flows use `Tachikoma.TestBackend`
with re-render after every `update!`.

## Testing notes

| Kind | How |
|------|-----|
| Pure WECO / stats | May raw-include `spc_workbench.jl` (legacy path) |
| CSV / JSON I/O | **`using TachikomaTUI` only** |
| UI | `TestBackend` + `find_text` / `row_text` / `char_at` |
| Fixtures | `test/fixtures/spc/` |
