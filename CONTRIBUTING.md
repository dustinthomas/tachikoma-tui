# Contributing

## Verification gates (after `src/` changes)

```bash
# 1. Full suite (hello + classic SPC + workbench)
julia --project=. test/runtests.jl

# 2. App smoke
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'

# 3. Workbench smoke (when touching workbench)
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo()'
```

Never claim green without running these in-session. Do not flip `seed_demos`
defaults. Live toggle convention (PR3): **`g`/`G` only** (not `L` — LSL edit).

## Testing conventions

| Area | Rule |
|------|------|
| Layout | `test/test_<feature>.jl`, wire via `include` in `test/runtests.jl` |
| Framework | `Test` stdlib; Supposition for PBT where useful |
| UI | `Tachikoma.TestBackend` only — re-render after every `update!` |
| Inspect | `find_text` / `row_text` / `char_at` / `visual_rows` |
| I/O tests | **`using TachikomaTUI`** (package module) — do not raw-include I/O into Main alongside the package |
| Fixtures | `test/fixtures/spc/` (CSV / JSON samples) |
| Drive UI | exclusively `update!(m, KeyEvent(...))` / `MouseEvent` |

### TestBackend checklist (UI PRs)

1. Headless `TestBackend` render — not manual “looks fine” alone.
2. Re-render after every `update!` before visual asserts.
3. Modal / overlay no-bleed (no dashboard chrome under help/config/library).
4. Small-terminal guards (`TestBackend(18, 5)` etc.) do not crash.
5. Elm contract: `@kwdef mutable struct … <: Model`, `should_quit`, `update!`, `view`.

See `.grok/docs/tachikoma-ui-testing.md` and `.grok/docs/tachikoma-core.md`.

## Formatting

Install JuliaFormatter (dev-only; **not** a runtime dep):

```bash
julia -e 'using Pkg; Pkg.add("JuliaFormatter")'
```

Format **touched files** before merge (do not mass-reformat the repo in a feature PR):

```bash
julia -e 'using JuliaFormatter; format("src/your_file.jl")'
```

Project config: `.JuliaFormatter.toml` (indent=4, margin=92).

## Documentation

- Public API: `"""..."""` docstrings on exported functions/types.
- Documenter lives in `docs/` (separate env). Sources: `docs/src/`. **HTML output
  `docs/build/` is committed** so operators get browser docs after `git pull`
  without a Documenter install. After editing docs sources:
  `julia --project=docs docs/make.jl`, then commit both sources and `docs/build/`.
- README: quick start / runners / gates. Documenter: concepts, schema, API.

## Suite wiring note (KD22 / KD24)

- `test/test_spc.jl` runs in an isolated `module TestSPCChart` so `using TachikomaTUI`
  does not collide with pure workbench tests that still `include("../src/spc_workbench.jl")`.
- **Do not remove the module wrapper** until pure workbench tests stop raw-including
  `src/spc_workbench.jl` (flattening into Main re-breaks the suite).
- Prefer package load for new tests; pure raw-include may remain until a consolidation PR.
