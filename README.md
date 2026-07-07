# tachikoma-tui

A fresh **Julia + Tachikoma.jl TUI** project bootstrapped with the full Grok agentic workflow.

## Quick Start

```bash
# Activate and run tests (always use --project=.)
julia --project=. test/runtests.jl

# Launch the starter TUI
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
```

In the TUI:
- `space`, `+`, or `↑` → increment counter
- `r` → reset
- `q` or `Esc` → quit

## Grok Agentic Workflow (2026-07)

This project ships the current single-agent + verifier workflow:

- `AGENTS.md` — full rules (read this)
- `.grok/config.toml`, `personas/`, `skills/`, `docs/`, `hooks/`
- `/prime` — orient yourself
- `/test`, `/review`, `/commit`, `/tdd`
- Bundled: `/implement`, `/design`, `/execute-plan`

See `.grok/docs/agentic-workflow-2026-07.md` for rationale.

**Verification gates** (after src/ changes):
1. Full test suite green
2. App runs (`hello_tachikoma()` or your main entry)
3. Independent verifier review of diff

## Project Structure

```
.
├── .grok/                 # Agentic workflow (config, skills, personas, safety)
├── src/
│   ├── TachikomaTUI.jl    # Main module + reexports
│   └── hello.jl           # Minimal starter TUI (counter demo)
├── test/
│   ├── runtests.jl
│   └── test_hello.jl      # TestBackend + model tests
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

## Next Steps

- Run `/prime` in a Grok session here.
- Build your first real feature using the tiered workflow.
- Replace `hello.jl` or add beside it.

## SPC Chart Demo (full interactive + live)

```bash
# Static (great for gates/tests)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.static_spc_demo()'

# Full live + mouse (recommended)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_demo()'
```

Features (per design):
- Seeded SPC data with control limits (UCL/LCL), violations.
- Canvas rendering: data line, dashed limits, violation markers, crosshair.
- Discrete data points use distinct ● (in-control) / ◆ (OOC) markers overlaid on cells.
- Mouse: hover (details + crosshair + tooltip window), click for persistent ┃ vertical (selected), left-drag pan, wheel zoom.
- Live updates (tick-driven append when not paused).
- Arc+needle gauges, side panel stats/legend, StatusBar footer.
- Keys: p pause, r/z reset, arrows pan, q quit.
- Fully TestBackend testable; follows Elm update!/view.

See `design-spc-interactive-chart.md` for the full PR plan and rationale.

---

Bootstrapped by copying the Grok agentic workflow from `julia-tachikoma-ui-test` (2026-07-07).
