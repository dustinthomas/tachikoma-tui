# TachikomaTUI

Julia + [Tachikoma.jl](https://kahliburke.github.io/Tachikoma.jl/dev/) TUI apps
shipped by this project.

## Apps

- **Hello** — minimal counter demo (`hello_tachikoma()`)
- **SPC Chart** — interactive SPC chart with live mode (`spc_demo()`, `static_spc_demo()`)
- **SPC Workbench** — multi-chart WECO workbench (`spc_workbench_demo()`, `spc_workbench()`)

## Quick start

```julia
using TachikomaTUI

hello_tachikoma()          # starter counter
static_spc_demo()          # classic SPC (static / gate-friendly)
spc_workbench_demo()       # workbench triple-demo dashboard (paused)
```

Load a saved session:

```julia
using TachikomaTUI
spc_workbench(workbench = "session.json")
# or construct without launching:
m = load_workbench("session.json")
```

## Documentation map

- [SPC Workbench](@ref) — runners, keys, live toggle, CSV format, JSON schema v1
- [Tutorial path](@ref) — blank slate → PECVD CSV charts (R3–R4)
- [Recording demos](@ref) — Tachikoma `.tach` capture; Hello + workbench recorders
- [API Reference](@ref) — public exports via Documenter `@autodocs`
- Repository `README.md` — verification gates, formatting, agent workflow
- Repository `docs/user/` — rough **operator** guides (getting started, workbench, I/O)
- Repository `docs/ROADMAP.md` — shipped vs in flux vs backlog
- Repository `docs/APP_WALKTHROUGH.md` — developer functionality walkthrough
- Repository `docs/design/recording-docs-plan.md` — plan to grow captures beyond Hello

## Conventions (locks)

| Topic | Rule |
|-------|------|
| Live toggle | **`g` / `G` only** — never `L` (`L` is LSL edit) |
| Seed demos | Default `seed_demos = :triple` — never flip without product decision |
| I/O tests | `using TachikomaTUI` only — do not raw-include `spc_workbench_io.jl` |
| Excel | **Out of scope** — CSV + JSON only long-term |
