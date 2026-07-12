# Data import & export (rough)

How to get measurement data **into** and **out of** the SPC Workbench.

> Contract detail (field tables, fail-closed rules): [../src/spc-workbench.md](../src/spc-workbench.md)  
> Product flux: [../ROADMAP.md](../ROADMAP.md)

**No Excel.** Use **CSV** for series/table ingress and **JSON** for full sessions.

---

## Quick reference

| Task | Where | Key / API |
|------|--------|-----------|
| Import CSV into a chart | Library | **`i`** |
| Export chart series CSV | Library | **`e`** |
| Save session | Library | **`w`** |
| Load session | Library | **`W`** (or start with `spc_workbench(workbench=…)`) |
| Inspect table | Dashboard | **`d`** |
| Rematerialize from table | Table grid | **`r`** |
| Apply chart maps from table | Builder | **`a`** |

---

## CSV import (series-first)

### What the importer expects

Phase A policy — simple and strict:

1. Prefer a header column named **`Value`** (case-sensitive).
2. Or a **single-column** file (header optional) of numbers.
3. Delimiter: **comma**.
4. Newlines: `\n` or `\r\n`; UTF-8 BOM stripped; empty lines skipped.
5. Non-numeric cells: warned; if **no** good floats → error (`:all_invalid`).
6. Size limit: **50 000** rows (above → `:too_large`).

**Not supported (for now):** full RFC4180 quoted-field edge cases, XLSX, column-picker UI.

### Minimal example

```text
Value
100.1
99.8
100.4
```

Repo fixture: `test/fixtures/spc/sample_value.csv`

### Import from the TUI

1. Open library: **`m`**
2. Select the target chart (or add one with **`a`**)
3. Press **`i`**, type the path, Enter
4. On success: series replaced (default), viewport refit, **live off** for that chart, session **paused**
5. Status line should look like `imported N values from …`
6. On failure: charts are not half-updated; look for `import err: …`

### Import when starting Julia

```julia
using TachikomaTUI

# New chart from CSV (also available as demo option)
spc_workbench_demo(load = "test/fixtures/spc/sample_value.csv")

spc_workbench(load = "path/to/data.csv", paused = true)
```

Programmatic helpers (from package load):

```julia
using TachikomaTUI
# parse_csv_table, import_csv_into_chart!, import_csv_new_chart!, …
```

### Multi-column CSVs

Extra columns are kept on the in-memory **SharedTable** when multi-column ingress is used. Map them in the **builder** (`b`):

| Builder field | Typical use |
|---------------|-------------|
| Value col | Measurement (`Value`) |
| N col | Sample size (attribute charts) |
| Tool col | Tool id for filters / materialize |
| Time col | Timestamp / labels |
| Lot col | Group key for X̄ table subgroups |
| Tools (csv) | Which tool ids this chart is assigned |

Then **Apply** (`a`) to materialize. Cell edits in the table grid also need **`r`** (or builder apply) before the chart series updates.

---

## Sample templates

Blank header-only templates under `test/fixtures/spc/templates/`:

| File | Header (summary) |
|------|------------------|
| `template_generic.csv` | Timestamp, Tool, Lot, Wafer, Chip, Value, Defects, n |
| `template_tool.csv` | Timestamp, Tool, Lot, Wafer, Value, Defects, n |
| `template_size_bin.csv` | Timestamp, Tool, Lot, Wafer, Value, Units, Defects, n |

Copy a template, fill rows in any editor, import via library **`i`**.  
**Size-binning UI** may still be backlog — the template is for data shape readiness.

---

## CSV export

From library (**`e`**):

- Writes a simple series file: header `Value` + one float per line
- Source chart: **library selection** when in library mode; otherwise active chart

Use this for a portable series snapshot, not a full multi-column table dump.

---

## JSON session (schema v1)

Save/load the **whole workbench**: charts, active index, tools, optional SharedTable, prefs, WECO defaults, pause flag, etc.

### From the TUI

| Key | Action |
|-----|--------|
| **`w`** | Save — path prompt (e.g. `session.json`) |
| **`W`** | Load — replaces session content (fail closed on error) |

### From Julia

```julia
using TachikomaTUI

save_workbench(m, "session.json")           # nothing | "save err: …"
m = load_workbench("session.json")          # model | "load err: …"
load_workbench!(m, "session.json")          # in-place; nothing | error string

# Or launch directly:
spc_workbench(workbench = "session.json")
```

Dict form:

```julia
d = workbench_to_dict(m)
m2 = workbench_from_dict(d)       # new model | error String
err = workbench_from_dict!(m, d)  # nothing | error String
```

### What you must know

| Rule | Meaning |
|------|---------|
| **version = 1** | Required integer; other versions rejected |
| **charts non-empty** | Required |
| **Fail closed** | Bad file → error string; in-place load does not half-apply |
| **No auto-rematerialize** | Loaded `values` stay the display series; table is restored separately |
| **live_enabled** | Always written; if omitted on load → **false** (safe) |
| **Empty table** | Often omitted on save when empty |
| **Admins / passcodes** | Never used; ignored if present (HTML archives strip them) |

Full field tables: [../src/spc-workbench.md](../src/spc-workbench.md) (JSON session schema v1).

---

## HTML archive load (advanced)

The repo may ship or accept an HTML mockup archive with embedded state. Package APIs include `load_html_archive` / `html_state_to_workbench` style helpers.

- Intended for **migration / parity** with the reference HTML workbench  
- Strips admin/passcode concepts  
- Same “no auto-rematerialize” idea as JSON for table vs series  

Prefer JSON for normal operator save/load.

---

## After import checklist

1. **Viewport** — should span the new series; use `r`/`z` if the view looks wrong  
2. **Live** — expect off for that chart; use **`g`** only if you want live append again  
3. **Limits** — auto limits recompute from series on render; set **manual** in builder if needed  
4. **Specs** — set USL/Target/LSL (`u`/`t`/`l`) for Cpk / OOS  
5. **WECO** — enable rules `1`–`8` or config `c`  
6. **Save** — library **`w`** once the session looks right  

---

## Troubleshooting

| Message / symptom | Likely cause |
|-------------------|--------------|
| `import err: …` / all invalid | No numeric values; wrong column name (`Value` is case-sensitive) |
| `too_large` | More than 50k rows |
| `load err: …` | Not version 1, empty charts, or corrupt/malformed table |
| `save err: …` | Path/permission/disk issue |
| Chart empty after load | Session had empty `values`; or you expected table to rebuild series automatically |
| Filters hide everything | Clear with **`f`** / filter UI; check chart `tools` / owner / type |

---

## Privacy note

Session JSON and CSV can contain process measurements and tool ids. Treat saved files like any fab data export — don’t commit real production data to public repos.
