# TachikomaTUI — Roadmap & in-flux notes

> **Status:** Living rough notes (2026-07).  
> Update this file when product intent or shipped surface changes.  
> Design detail lives in root `design-spc-*.md` files; this page is the short map.

---

## Current state (usable today)

The **SPC Workbench** is the main app. On `master` you can already:

| Area | What works |
|------|------------|
| **Dashboard** | Multi-chart panes, `[`/`]` active switch, pan, WECO 1–8, specs (USL/Target/LSL), Cpk/OOS |
| **Dual secondary canvas** | Active I-MR / X̄-R / X̄-S can show MR/R/s under primary (pref `o`; height may compress neighbors) |
| **Classic mouse** | Hover, pan, zoom, selection on **primary** plot |
| **Library** | CRUD, activate chart, CSV import/export, JSON save/load, library mouse hit-test |
| **Builder** | Chart type, column maps, tools CSV, owner, subgroup size, limits mode, materialize |
| **Tools registry** | Master tool list (`x`); assign tools to charts in **builder**; public `replace_tools!` for external registries (FabTUI) |
| **SharedTable grid** | Inspect/edit cells (`d` from dashboard); explicit rematerialize |
| **Chart types** | I-MR, X̄-R, X̄-S, p, np, c, u (typed limits / series math) |
| **I/O** | Series-first CSV, JSON session schema **v1** (charts + optional table/tools/prefs), HTML archive load |
| **Live** | Session pause `p`; per-chart live **`g`/`G` only** (`L` = LSL) |
| **Classic SPC** | Separate single-chart demo (`spc_demo` / `static_spc_demo`) — keep untouched |
| **Hello** | Minimal counter starter |

**Preferred smoke run:**

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'
```

**Locks (do not “fix” without product decision):**

| Topic | Rule |
|-------|------|
| Live toggle | `g` / `G` only — never `L` |
| Seed demos | Default `seed_demos = :triple` |
| Excel | Out of scope long-term (CSV + JSON only) |
| Auto-rematerialize on load | Out — series values are display SoT until explicit rematerialize |
| Classic `src/spc.jl` | Separate product surface; do not break for workbench work |

---

## In flux / likely to change

Large work is still expected. Treat the following as **unstable** for user docs and external assumptions:

| Area | Why it may move |
|------|-----------------|
| **Key bindings** | New modes or denser chrome can re-home keys; authoritative list is `docs/src/spc-workbench.md` |
| **Dashboard layout** | Dual canvas already temporarily compresses multi-pane; further layout polish is fair game |
| **Builder / table UX** | More fields, validation, or workflow changes without schema bumps |
| **Help / keymap strings** | Track code; can lag slightly after features |
| **Attribute chart workflows** | Math exists; operator polish (n-column, prompts) may deepen |
| **Performance at large n** | Viewport/live caps and render paths may tighten |
| **Documenter user pages** | Rough markdown may move into `docs/src/` later |

**Safe to treat as more stable:**

- JSON schema **v1** field contracts (additive optional keys preferred over silent breaks)
- CSV series-first ingress (`Value` / single column) and fail-closed parse kinds
- Live = `g`/`G`, LSL = `l`/`L`, seed triple default
- Explicit materialize (builder apply / table `r`) — not auto on load

If a PR changes a **contract** (keys advertised to operators, JSON fields, CSV shape, runners), update in the **same PR**:

1. `docs/src/spc-workbench.md` (authoritative)
2. This file’s “Current state” / “Planned” tables if product intent shifted
3. Rough user docs under `docs/user/` when the operator path changes

---

## Planned / backlog (not a commitment)

Drawn from `design-spc-p2-polish-plan.md` and ongoing product direction. Many P2 core items have **already landed**; remaining themes:

| Item | Notes |
|------|--------|
| **Size binning** | Optional / niche fab (particle/defect → count series); pure + builder if capacity |
| **Global default-WECO editor UI** | Session `default_rules` already seeds `add_chart!`; dedicated editor / config tab may still grow |
| **Richer CSV** | Still deliberately simple (not full RFC4180); may improve quoted fields carefully |
| **Deeper HTML parity** | Only where TUI-appropriate; no admin auth, no Excel, no self-modifying HTML |
| **Docs polish** | Wire user guides into Documenter; reduce drift vs walkthrough |

**Explicit non-goals (locked):**

> **FabTUI boundary:** TachikomaTUI stays offline/demo-capable. No Fab HTTP or login here. External **FabTUI** will call `replace_tools!` (equipment) and `fill_shared_table!` / `shared_table_from_columns_rows` (series) after its own auth layer.

| Item | Disposition |
|------|-------------|
| Excel / XLSX | Out |
| Admin passwords / multi-user auth | **Out of TachikomaTUI scope** — production auth + equipment HTTP live in future **FabTUI** (depends on `replace_tools!` / public table loaders) |
| Permanent `view_mode=:focused` as product mode | Out (temporary dual height compress only) |
| Dual secondary canvas on **neighbor** panes | Out (height) |
| Auto-rematerialize charts on JSON/HTML load | Out |
| Changing classic SPC demo behavior | Out |

---

## Design docs (detail)

| File | Role |
|------|------|
| `design-spc-workbench-plan.md` | Original workbench + WECO design |
| `design-spc-html-gap-analysis.md` | HTML vs TUI inventory |
| `design-spc-html-parity-plan.md` | Parity PR architecture |
| `design-spc-gap-closure-plan.md` | Library / panes / filters shell |
| `design-spc-p2-polish-plan.md` | Dual canvas, tools, table, builder, backlog |

Historical “missing” claims in older design docs may already be shipped — trust **this file + current `src/` + `docs/src/spc-workbench.md`** over stale design prose when they conflict.

---

## Doc map

| Audience | Path |
|----------|------|
| **Operators (rough user guide)** | [`docs/user/`](user/README.md) |
| **Dev orientation** | [`docs/APP_WALKTHROUGH.md`](APP_WALKTHROUGH.md) |
| **Keys / CSV / JSON contracts** | [`docs/src/spc-workbench.md`](src/spc-workbench.md) |
| **Documenter home / API** | `docs/src/index.md`, `docs/src/api.md` |
| **Repo quick start / gates** | `README.md` |
