# Tutorial: blank slate → PECVD charts

Learn the workbench by starting **empty**, then loading three Film-PTPECVD01
series (oxide thickness, refractive index, HSQ thickness).

> Automated `.tach` captures of this path:  
> `julia --project=. scripts/record_tutorial_path.jl`  
> See also Documenter *Tutorial path* and *Recording demos*.

---

## Part A — Blank slate (chrome only)

### Launch

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:none)'
```

You should see **one empty Primary** chart, no PARAMS catalog, no demo series.

### Keys to try

| Key | What you should see |
|-----|---------------------|
| **`h`** | Help page |
| **`k`** | Keymap page |
| Esc / `q` | Back to dashboard (**from help/keymap/library** — does not quit) |
| **`m`** | Library — single empty chart |
| **`?`** | Expand footer key hints (stays on dashboard) |
| Esc on **dashboard** | **Quits** the app |

### Headless capture (optional)

```bash
julia --project=. scripts/record_blank_workbench.jl
# → agent_logs/blank_workbench.tach
```

---

## Part B — Hand-load PECVD data

### Data files (in repo)

| File | Parameter | Specs (USL / Target / LSL) |
|------|-----------|----------------------------|
| `test/fixtures/spc/pecvd/oxide_thickness_1_3um.csv` | Oxide thickness 1.3 µm | 1320 / 1300 / 1280 nm |
| `test/fixtures/spc/pecvd/refractive_index.csv` | Refractive index | 1.48 / 1.46 / 1.44 |
| `test/fixtures/spc/pecvd/hsq_thickness.csv` | HSQ thickness | 640 / 600 / 560 nm |

Columns: `Timestamp,Tool,Lot,Wafer,Parameter,Units,Value` — tool id **Film-PTPECVD01**.

Regenerate synthetic values:

```bash
julia --project=. test/fixtures/spc/pecvd/generate.jl
```

### Live walkthrough

1. Start blank (`seed_demos=:none`) as above.
2. **Optional tool registry:** `x` → `a` → id `Film-PTPECVD01` → description → Esc.
3. **Oxide into Primary:** `m` → `i` → type  
   `test/fixtures/spc/pecvd/oxide_thickness_1_3um.csv` → Enter → Esc.  
   Dashboard should show ~40 points.
4. **Name + specs:** `b` → edit **Name** → `Oxide Thickness 1.3um`. Esc.  
   Then `u`/`t`/`l` → 1320 / 1300 / 1280.  
   Builder **Tools (csv)** → `Film-PTPECVD01`.
5. **Refractive index:** `m` → `a` (new chart) → select it → `i` →  
   `test/fixtures/spc/pecvd/refractive_index.csv`.  
   Name `Refractive Index`; specs 1.48 / 1.46 / 1.44; tools as above.
6. **HSQ:** same pattern with `hsq_thickness.csv`; specs 640 / 600 / 560.
7. Cycle charts with **`[`** / **`]`**. Library **`m`** lists all three.
8. **Save session (optional):** library **`w`** → e.g. `pecvd_session.json`.

### API shortcut (same end state, no path typing)

For scripts, tests, and recordings we build the session in Julia:

```julia
using TachikomaTUI
m = make_pecvd_tutorial_workbench()   # 3 charts + tool + specs
# then either:
#   app(m)                            # interactive
# or record_pecvd_tutorial_demo(...)  # headless .tach
```

Headless capture:

```bash
julia --project=. scripts/record_pecvd_tutorial.jl
# → agent_logs/pecvd_tutorial.tach
```

---

## Part C — What this is *not*

| Alternate | When to use |
|-----------|-------------|
| `seed_demos=:fake_tool` | Instant product demo (PARAMS catalog, synthetic table) — no CSV files |
| `pecvd_all_params.csv` | Long multi-param dump; **do not** import as one chart (mixes series) |
| Default `:triple` | Random Primary/Secondary/Tertiary demos — not this tutorial |

Side Stats **PARAMS** appears for `:fake_tool` sessions, not for this pure CSV hand path
(each parameter is simply its own **chart** in the library).

---

## Next

- Operator reference: [workbench.md](workbench.md), [data-import-export.md](data-import-export.md)
- Recording plan: `docs/design/recording-docs-plan.md` (R5 = fake_tool product walkthrough)
