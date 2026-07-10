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
| `c` / `v` / `o` | Config WECO / Lines / Visual prefs |
| `u` / `t` / `l` | Edit USL / Target / **LSL** (`L` is LSL, not live) |
| `s` | Clear all spec limits |
| `1`…`8` | Toggle WECO rule N |
| `[` `]` | Switch active chart |
| `←` `→` | Pan viewport |
| `?` / `h` | Help overlay |
| `k` | Keymap page |

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

**Never** use `o` / `O` for open-file (those are Visual Preferences on the
dashboard). File keys are library `i` / `e` / `w` / `W` only.

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
| `default_rules` | no | WECO enable map (defaults applied if omitted) |
| `show_chart_lines` | no | CL / σ / specs visibility |
| `visual_prefs` | no | Series connector prefs |
| `paused` | no | Bool; default false if omitted |

### Per-chart object

| Field | Required | Notes |
|-------|----------|-------|
| `id` | **yes** | String |
| `name` | **yes** | String |
| `chart_type` | **yes** | Wire string: `I-MR`, `Xbar-R`, `Xbar-S`, `p`, `np`, `c`, `u` |
| `values` | **yes** | Array of numbers (may be empty) |
| `usl` / `target` / `lsl` | no | Number or null |
| `enabled_rules` | no | Object of rule-id → bool |
| `param` / `units` / `owner` | no | Strings |
| `tools` | no | Array of tool id strings |
| `limits_mode` | no | `"auto"` (default) or `"manual"` |
| `manual_cl` / `manual_ucl` / `manual_lcl` | no | Number or null |
| `subgroup_size` | no | Integer (default 5) |
| `live_enabled` | no | Always written on save; **omitted → false** on load |
| `viewport` | no | `{x0, x1, ylo, yhi}`; bootstrapped if missing |

### Load semantics

- **Fail closed:** corrupt / unsupported version / empty charts → error string;
  in-place load does not mutate charts.
- **Never** deserialize `admins` / passcodes (ignored if present).
- Unknown chart keys ignored.
- `load_workbench!` replaces charts/active/tools/optional prefs; clears UI
  ephemerals (config/edit/hover/drag/prompt); preserves `rng`, `tick`, `quit`,
  geometry, `live_max`.
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
