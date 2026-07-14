# SPC Workbench

Multi-chart WECO / capability workbench: interactive I-MR explorer with chart
library metadata, live append gates, and JSON session persistence (schema v1).
CSV series import/export land with the I/O feature PRs; formats below are the
locked contracts.

## Runners

```julia
using TachikomaTUI

# Seeded triple-demo dashboard (static / gate-friendly)
spc_workbench_demo()

# Interactive; optional pause and schema-v1 load
spc_workbench(; paused = true)
spc_workbench(workbench = "session.json")
```

`seed_demos` defaults to `:triple` (Primary / Secondary / Tertiary). Do **not**
change that default. Use `:single` or `:none` only in explicit constructs.

## Keys

### Dashboard (always available)

| Key | Action |
|-----|--------|
| `q` / Esc | Quit (dashboard only) |
| `p` / `P` | Pause / resume live tick |
| **`g` / `G`** | Toggle active chart `live_enabled` (**not `L`**) |
| `r` / `z` | Reset viewport (full range + auto Y) |
| `c` / `v` / `o` | Config → Rules / Lines / Visual |
| **`e` / `E`** | Config → **Saved** (named graph configs; load → dashboard) |
| Config `e` | Jump to Saved section |
| Config `s` | Name-save current graph set (session upsert) |
| Config `w` | Path prompt → **file-save** graph config JSON (`kind=graph_preset`) |
| Config `W` | Path prompt → **file-load** graph config → upsert by name → apply → dashboard |
| `u` / `t` / `l` | Edit USL / Target / **LSL** (`L` is LSL, not live) |
| `s` | Clear all spec limits |
| `1`…`8` | Toggle WECO rule N |
| `[` `]` | Switch active chart |
| `←` `→` | Pan viewport |
| `m` / `M` | Open chart library |
| `x` / `X` | Open tools registry |
| `f` / `F` | Cycle filter prompt / clear filters |
| `b` / `B` | Open chart builder |
| `?` / `h` | Help overlay |
| `k` | Keymap page |
| **`d` / `D`** | Open SharedTable grid (`view_mode=:table`) |

### Dual secondary canvas (active plot)

I-MR / X̄-R / X̄-S charts can show a **secondary series canvas** (MR / R / s) stacked
under the **active** plot only (neighbors stay single-series when drawn).

| Item | Behavior |
|------|----------|
| Pref | Visual Preferences (`o`) → **Secondary canvas (MR/R/s)** (default **on**) |
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

**Never** use `o` / `O` for open-file (those are Visual Preferences on the
dashboard). File keys are library `i` / `e` / `w` / `W` only.

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
| `default_rules` | no | Session WECO enable map for **new** charts (`add_chart!` seed). Distinct from per-chart `enabled_rules`. Omitted → module `DEFAULT_WECO_RULES`. |
| `show_chart_lines` | no | CL / σ / specs visibility |
| `chart_line_styles` | no | Per-line style ids (`solid` / `dotted` / `dashed` / `long_dash`); omitted → defaults |
| `visual_prefs` | no | Series connectors + `secondary_canvas` (dual MR/R/s under active) |
| `graph_presets` | no | Array of named graph presets (whole graph set); **omitted on save when empty** |
| `paused` | no | Bool; default false if omitted |
| `table` | no | SharedTable `{columns, rows}`; **omitted on save when empty**; missing/null → empty on load |

### Graph preset object (`graph_presets[]`)

Named snapshot of the **whole graph config set** (no series data): what is drawn,
line styles, visual prefs, and WECO rules to calculate.

**Config → Saved** (`e` from dashboard, or `e` from Config; Tab also cycles to Saved):

| Key | Action |
|-----|--------|
| `s` | **Popup** name prompt — save/upsert current graph set (session list) |
| `w` | **Path prompt** — write standalone graph-config JSON (basename without extension becomes `name`) |
| `W` | **Path prompt** — load file → upsert by payload `name` → apply → dashboard |
| `↑`/`↓` | Select a saved config |
| `Enter` / `l` / `a` / **Space** | **Load** selected named → dashboard (R2) |
| `d` then `y` | Delete selected named config (not a chart) |
| Esc / `q` | Close Config (no quit) |

Load applies to active-chart WECO rules + session `default_rules`.

Named-list success events keep `"preset …"` prefixes. File path success uses
`"saved graph config <path>"` / `"loaded graph config <path>"`. Path prompts
prefill `last_graph_config_path` (never a silent default write). Fail-closed on
bad/empty path (prompt stays open; model + list unchanged on load fail).

| Field | Required | Notes |
|-------|----------|-------|
| `name` | **yes** | Non-empty string (upsert key) |
| `show_chart_lines` | no | Bool map; defaults if omitted |
| `chart_line_styles` | no | Style map; unknown style string → fail-closed |
| `visual_prefs` | no | Bool map; defaults if omitted |
| `enabled_rules` | no | WECO map captured from active chart at save time |

Standalone file helpers: `save_graph_preset(p, path)` / `load_graph_preset(path)`
write `{kind: "graph_preset", version: 1, …fields}`. Load also accepts
`kind: "graph_config"` as an alias; write still emits `graph_preset`.

### Per-chart object

| Field | Required | Notes |
|-------|----------|-------|
| `id` | **yes** | String |
| `name` | **yes** | String |
| `chart_type` | **yes** | Wire string: `I-MR`, `Xbar-R`, `Xbar-S`, `p`, `np`, `c`, `u` |
| `values` | **yes** | Array of numbers (may be empty) |
| `usl` / `target` / `lsl` | no | Number or null |
| `enabled_rules` | no | Per-chart WECO map (rule-id → bool). Not the session `default_rules`. |
| `param` / `units` / `owner` | no | Strings |
| `tools` | no | Array of tool id strings |
| `limits_mode` | no | `"auto"` (default) or `"manual"` |
| `manual_cl` / `manual_ucl` / `manual_lcl` | no | Number or null |
| `subgroup_size` | no | Integer (default 5) |
| `live_enabled` | no | Always written on save; **omitted → false** on load |
| `source` | no | `"series"` (default) or `"table"` provenance |
| `col_value` / `col_n` / `col_tool` / `col_time` | no | Column maps for table materialize |
| `col_lot` | no | Always written on save; **omitted → `""`** on load; X̄ group column |
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
