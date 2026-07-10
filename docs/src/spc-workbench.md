# SPC Workbench

Workbench reconstruction of the HTML SPC mockup: multi-chart dashboard, WECO
rules, capability (Cpk), mouse/keyboard interactions, and (in later PRs) CSV/JSON
I/O + chart library.

## Runners

```julia
using TachikomaTUI

# Seeded triple-demo dashboard (static / gate-friendly)
spc_workbench_demo()

# Interactive (optional live)
spc_workbench(; paused = true)
```

## Keys (overview)

| Key | Action |
|-----|--------|
| `q` / Esc | Quit |
| `p` | Pause / resume live tick |
| `r` / `z` | Reset viewport |
| `g` / `G` | Live toggle (not `L`) |
| `?` / `h` | Help overlay |

Full keymap and library workflow pages land with feature PRs.

## I/O (planned)

- CSV: column header `Value` (fixtures under `test/fixtures/spc/`)
- JSON chart library schema (v1) documented when I/O PRs land
- **I/O tests must use `using TachikomaTUI`** (package load) — do not raw-include
  `spc_workbench_io.jl` into the same process that also loads the package module

## WECO / stats

Pure functions (`weco_detect`, `compute_limits_and_zones`, `compute_capability`, …)
are exported from `TachikomaTUI` and covered by `test/test_spc_workbench.jl`.
