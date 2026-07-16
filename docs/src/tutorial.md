# Tutorial path

Operator learning path:

1. **Blank workbench** → chrome only  
2. **PECVD CSV hand path** → import three series  
3. **`:fake_tool` PARAMS** → product param catalog + Compare  

Step-by-step guides:

| Guide | Topic |
|-------|--------|
| [`docs/user/tutorial-blank-to-pecvd.md`](../../user/tutorial-blank-to-pecvd.md) | Blank + CSV hand path (R3–R4) |
| [`docs/user/tutorial-fake-tool-params.md`](../../user/tutorial-fake-tool-params.md) | Film-PTPECVD01 PARAMS / Compare (R5) |

This page is the Documenter entry point and the recording index.

---

## Open this site from the app

After `julia --project=docs docs/make.jl` once:

- In the workbench: **`h`** then **`O`** (opens this tutorial in your browser)
- Or: **`k`** then **`O`** (opens docs home)
- CLI: `julia --project=. scripts/open_docs.jl tutorial`

```julia
using TachikomaTUI
open_local_docs(page = "tutorial")   # system browser, file:// URL
```

---

## Quick launch

```julia
using TachikomaTUI

# A — empty Primary (no demo series)
spc_workbench_demo(seed_demos = :none)

# B — same end-state as the hand CSV walkthrough (API-built session)
m = make_pecvd_tutorial_workbench()
# app(m)

# C — product PARAMS catalog (no CSV files)
spc_workbench_demo(seed_demos = :fake_tool)
# or: make_fake_tool_workbench()
```

From the shell:

```bash
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:none)'
julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:fake_tool)'
```

---

## Deterministic recordings

```bash
# R3 + R4 + R5
julia --project=. scripts/record_tutorial_path.jl

# Or separately
julia --project=. scripts/record_blank_workbench.jl
julia --project=. scripts/record_pecvd_tutorial.jl
julia --project=. scripts/record_fake_tool_tutorial.jl
```

| API | What it captures |
|-----|------------------|
| `record_blank_workbench_demo` | Help → keymap → library on empty Primary |
| `record_pecvd_tutorial_demo` | Library / chart cycle / tools / builder after three CSV imports |
| `record_fake_tool_tutorial_demo` | PARAMS focus, cycle, pin, Compare toggle, library |

```julia
using TachikomaTUI
record_blank_workbench_demo("agent_logs/blank_workbench.tach")
record_pecvd_tutorial_demo("agent_logs/pecvd_tutorial.tach")
record_fake_tool_tutorial_demo("agent_logs/fake_tool_tutorial.tach")
```

**Why API-seed for PECVD CSVs?** Typing long paths into the library import prompt is a
poor fit for frame-indexed `record_app` events. The tutorial **text** still
teaches `m` → `i` → path; the **recording** uses `make_pecvd_tutorial_workbench`
then films navigation only.

---

## Fixture data

Under `test/fixtures/spc/pecvd/`:

- `oxide_thickness_1_3um.csv`
- `refractive_index.csv`
- `hsq_thickness.csv`

Tool id: **Film-PTPECVD01**. See the user tutorial for USL/Target/LSL values.

---

## Related

- [Recording demos](@ref) — Hello seed + pattern to copy  
- [SPC Workbench](@ref) — full product contract  
- `docs/design/recording-docs-plan.md` — R5 fake_tool next  
