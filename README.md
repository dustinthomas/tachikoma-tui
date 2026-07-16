# tachikoma-tui

A fresh **Julia + Tachikoma.jl TUI** project bootstrapped with the full Grok agentic workflow.

## Quick Start

```bash
# Activate and run tests (always use --project=.)
julia --project=. test/runtests.jl

# Launch the starter TUI
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'

# Headless screen capture of the Hello demo → .tach (Tachikoma recorder)
julia --project=. scripts/record_hello_demo.jl

# Tutorial path recordings: blank + PECVD CSV + fake_tool PARAMS
julia --project=. scripts/record_tutorial_path.jl

# Local Documenter HTML in the browser (private app — not a public site)
# Prebuilt under docs/build/ (committed) — works after git pull with no build step
julia --project=. scripts/open_docs.jl      # or: open_local_docs()
# In workbench: h then O (tutorial) · k then O (home)
# After editing docs/src: julia --project=docs docs/make.jl  then commit docs/build
```

Operator tutorial (blank → three PECVD CSVs): `docs/user/tutorial-blank-to-pecvd.md`.


In the TUI:
- `space`, `+`, or `↑` → increment counter
- `r` → reset
- `q` or `Esc` → quit

## SPC runners

```bash
# Classic SPC chart — static (gates/tests)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.static_spc_demo()'

# Classic SPC chart — live + mouse
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_demo()'

# Workbench — seeded triple-demo dashboard (preferred gate smoke)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'

# Workbench — interactive (optional live; paused=true for static)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench(paused=true)'
```

Live toggle convention (locks at PR3): **`g` / `G` only** (not `L` — `L` is LSL
edit). Do not change `seed_demos` defaults without an explicit product decision.

## Verification gates

After any `src/` change affecting startup / `update!` / `view`:

1. **Full suite** (must exit 0):
   ```bash
   julia --project=. test/runtests.jl
   ```
   Suite includes `test_hello.jl`, `test_spc.jl` (classic SPC), and
   `test_spc_workbench.jl`.
2. **App smoke**:
   ```bash
   julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
   ```
3. **Workbench smoke** (when touching workbench):
   ```bash
   julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'
   ```
4. Independent verifier review of the actual `git diff` when using the agentic workflow.

Authoritative rules: `AGENTS.md` + `CLAUDE.md`. See also `CONTRIBUTING.md`.

## Testing conventions

- Layout: `test/test_<feature>.jl`, wired from `test/runtests.jl`.
- UI: `Tachikoma.TestBackend` — re-render after every `update!`; assert with
  `find_text` / `row_text` / `char_at` / `visual_rows`.
- **I/O tests use `using TachikomaTUI`** (package load). Do not raw-include I/O
  modules into the same process that also loads the package.
- Fixtures: `test/fixtures/spc/` (e.g. `sample_value.csv` with a `Value` column).

## Formatting (JuliaFormatter)

Dev-only — **not** a runtime dependency of TachikomaTUI:

```bash
julia -e 'using Pkg; Pkg.add("JuliaFormatter")'
julia -e 'using JuliaFormatter; format("src/your_file.jl")'   # format touched files
```

Config: `.JuliaFormatter.toml` (indent=4, margin=92). Do not mass-reformat the
repo in a feature PR.

## Documentation

| Doc | Audience |
|-----|----------|
| [`docs/user/`](docs/user/README.md) | **Operators** — getting started, workbench, CSV/JSON (rough) |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Shipped vs in flux vs backlog |
| [`docs/APP_WALKTHROUGH.md`](docs/APP_WALKTHROUGH.md) | Dev-oriented functionality walkthrough |
| `docs/src/spc-workbench.md` | Authoritative keys + CSV + JSON schema v1 |
| `README.md` (this file) | Quick start and verification gates |

Documenter lives under `docs/` (separate env, not a runtime dep). **Prebuilt HTML
is committed in `docs/build/`** so workbench `O` / `scripts/open_docs.jl` work
after `git pull` without installing Documenter. When you change `docs/src` or
`docs/make.jl`, rebuild and commit the output:

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl   # must exit 0; then commit docs/build/
```

Documenter pages today: `docs/src/index.md` (home), `docs/src/spc-workbench.md`
(keys, CSV, JSON schema v1), `docs/src/api.md` (`@autodocs`). Rough user guides
and the roadmap live as markdown under `docs/` / `docs/user/` (not yet all wired
into Documenter). Path dep for TachikomaTUI is declared in `docs/Project.toml`
(`[sources]`).

## Grok Agentic Workflow (2026-07)

This project ships the current single-agent + verifier workflow:

- `AGENTS.md` — full rules (read this)
- `.grok/config.toml`, `personas/`, `skills/`, `docs/`, `hooks/`
- `/prime` — orient yourself
- `/test`, `/review`, `/commit`, `/tdd`
- Bundled: `/implement`, `/design`, `/execute-plan`

See `.grok/docs/agentic-workflow-2026-07.md` for rationale.

## Project Structure

```
.
├── .grok/                 # Agentic workflow (config, skills, personas, safety)
├── docs/                  # Documenter scaffold (PR0; full green @ PR11)
├── src/
│   ├── TachikomaTUI.jl    # Main module + reexports
│   ├── hello.jl           # Minimal starter TUI (counter demo)
│   ├── spc.jl             # Classic interactive SPC chart
│   └── spc_workbench.jl   # WECO workbench
├── test/
│   ├── runtests.jl        # Full suite entry (hello + spc + workbench)
│   ├── test_hello.jl
│   ├── test_spc.jl
│   ├── test_spc_workbench.jl
│   └── fixtures/spc/      # Sample CSV / JSON for I/O PRs
├── CONTRIBUTING.md
├── Project.toml
├── AGENTS.md
└── README.md
```

## Adding Your Own TUI

1. Create `src/my_app.jl` with `@kwdef mutable struct MyModel <: Model`, `should_quit`, `update!`, `view`.
2. Export and include it from `TachikomaTUI.jl`.
3. Add TestBackend coverage in `test/`.
4. Add runner function `my_app()` that calls `app(MyModel())`.
5. Update tests and run gates.

## Tachikoma.jl Essentials

- Elm architecture in the terminal.
- Excellent `TestBackend` for 100% deterministic, tty-free UI testing.
- Widgets, layouts, Canvas, themes, etc.
- Full docs: https://kahliburke.github.io/Tachikoma.jl/dev/

## SPC Chart Demo (classic)

Features (classic `spc.jl` chart):
- Seeded SPC data with control limits (UCL/LCL), violations.
- Canvas rendering: data line, dashed limits, violation markers, crosshair.
- Discrete data points use distinct ● (in-control) / ◆ (OOC) markers overlaid on cells.
- Mouse: hover (details + crosshair + tooltip window), click for persistent ┃ vertical (selected), left-drag pan, wheel zoom.
- Live updates (tick-driven append when not paused).
- Arc+needle gauges, side panel stats/legend, StatusBar footer.
- Keys: p pause, r/z reset, arrows pan, q quit.
- Fully TestBackend testable; follows Elm update!/view.

---

Bootstrapped by copying the Grok agentic workflow from `julia-tachikoma-ui-test` (2026-07-07).
