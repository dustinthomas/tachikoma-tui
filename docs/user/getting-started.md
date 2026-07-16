# Getting started

Rough operator guide for launching TachikomaTUI apps.

## Requirements

- **Julia** 1.10+ (see `Project.toml` `julia` compat)
- A real terminal (mouse support is useful for charts)
- This repository checked out, with the project environment available

From the repo root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Always use **`julia --project=.`** so the package and deps resolve correctly.

---

## Which app should I open?

| Goal | Command |
|------|---------|
| Try the **full workbench** (recommended) | `spc_workbench_demo()` |
| **Tutorial:** blank → PECVD CSVs | `spc_workbench_demo(seed_demos=:none)` then [tutorial-blank-to-pecvd.md](tutorial-blank-to-pecvd.md) |
| **Tutorial:** fake-tool PARAMS | `spc_workbench_demo(seed_demos=:fake_tool)` then [tutorial-fake-tool-params.md](tutorial-fake-tool-params.md) |
| Workbench with live ticks | `spc_workbench()` or `spc_workbench(paused=true)` |
| Load a saved session | `spc_workbench(workbench="path/to/session.json")` |
| Simple single control chart | `static_spc_demo()` or `spc_demo()` |
| Tiny counter demo | `hello_tachikoma()` |

### Workbench (start here)

Paused triple-chart demo — good first look, no racing live points:

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'
```

Interactive (live append can run unless paused):

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench(paused=true)'
```

### Classic single SPC chart

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.static_spc_demo()'
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_demo()'
```

### Hello starter

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
```

Keys: `space` / `+` / `↑` increment, `r` reset, `q` quit.

**Headless recording** (Tachikoma `.tach` capture of the same app):

```bash
julia --project=. scripts/record_hello_demo.jl
```

See Documenter page *Recording demos* and `docs/design/recording-docs-plan.md`.

---

## Local HTML docs in the browser

This app is private/local. Full docs are **Documenter** HTML under `docs/build/`
(not a public website).

**Build once** (from repo root):

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

**Open from the workbench:** press **`h`** (help) or **`k`** (keymap), then **`O`**.
- Help → **O** opens the **tutorial** page  
- Keymap → **O** opens the **docs home**  
Status line reports success or “docs not built…”.

**Open from the shell:**

```bash
julia --project=. scripts/open_docs.jl
julia --project=. scripts/open_docs.jl tutorial
```

Or in Julia: `using TachikomaTUI; open_local_docs()` / `open_local_docs(page="tutorial")`.

---

## Terminal tips

- Prefer a window at least **~80×24** cells. Smaller terminals still run but charts and dual panes get tight.
- Enable mouse reporting if your terminal supports it (most modern terminals do).
- Quit the workbench with **`q` or Esc from the main dashboard** only. Inside library/builder/help, those keys usually **close the page**, not the whole app.

---

## First five minutes in the workbench

1. Launch `spc_workbench_demo()`.
2. Press **`?`** or **`h`** for help; **`k`** for a keymap page.
3. Use **`[`** / **`]`** to switch the active chart among the three demos.
4. Press **`1`–`8`** to toggle Western Electric (WECO) rules on the active chart.
5. Open the **library** with **`m`** (chart list / import paths). Esc back to dashboard.
6. When done, Esc/q back to dashboard if needed, then **`q`** to quit.

Next: [Workbench guide](workbench.md) · [Data import & export](data-import-export.md)

---

## Load your own data (preview)

1. Prepare a CSV with a **`Value`** column (see [data import](data-import-export.md)).
2. In the workbench: **`m`** → library → **`i`** → type the file path → Enter.
3. Import turns that chart’s live append **off** and pauses the session so you can inspect calmly.

Or from Julia:

```julia
using TachikomaTUI
spc_workbench(load = "test/fixtures/spc/sample_value.csv", paused = true)
```

---

## If something fails

| Symptom | What to try |
|---------|-------------|
| Package not found | Run from repo root with `julia --project=.` |
| Import error message | Check CSV has `Value` or a single numeric column; see import guide |
| Load/save error | JSON must be schema **version 1** with a non-empty `charts` array |
| Keys do nothing | You may be in a prompt (type path) or another mode — Esc cancels/closes |
| Live won’t stop | **`p`** pauses session ticks; **`g`** toggles **per-chart** live (not `L`) |

Still stuck: developers should run `julia --project=. test/runtests.jl` and check `docs/ROADMAP.md`.
