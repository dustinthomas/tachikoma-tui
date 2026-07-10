# Design: SPC Workbench TUI — WECO Rules Translation + Rich Interactive Charts

**Author:** Grok Build (systems architect)  
**Date:** 2026-07-07  
**Status:** Draft  
**Related:** `/design` task per user request referencing `spc-html-mocup/SPC_workbench_2026-06-18-20-46.html` (3171 lines) and existing `src/spc.jl`

---

## Overview

This design proposes a new, separate iteration of Statistical Process Control (SPC) charts for the TachikomaTUI project. The reference is the self-contained web "SPC workbench" mockup at `spc-html-mocup/SPC_workbench_2026-06-18-20-46.html`, which implements a realistic SPC application with:

- All 8 Western Electric (WECO / Nelson) rules with precise logic, per-chart toggles, and violation reporting.
- Chart types focused on I-MR (Individuals + Moving Range), X̄-R, X̄-S (with subgrouping support).
- Data model: tabular rows (Lot/Wafer/Chip/Tool/Timestamp/Value + metadata + optional `n`).
- Auto vs. manual control limits, zone A/B/C awareness, spec limits (USL/LSL/Target) + Cpk/Ppk capability.
- Builder UI, multi-chart registry (clone/edit/delete), tools registry, import/export (xlsx via SheetJS + full archive), persistence concepts.
- UI: masthead, tabbed panels (Charts, WECO rules, Builder, Data), chart-cards containing stats + canvas/svg plot + violations list.

The solution translates **most of the functionality** into idiomatic Julia + Tachikoma TUI form (not a pixel clone). The existing SPC implementation (`src/spc.jl`, `SPCModel`, `static_spc_demo()`, `spc_demo()`, `generate_spc_data`, etc.) **must remain 100% untouched** in behavior, code paths, and exports.

**Key technical approach:**
- New files only: `src/spc_workbench.jl` (core), new public runners, `test/test_spc_workbench.jl` (or additive), updates only additive to `src/TachikomaTUI.jl` + `src/precompile.jl`.
- Strong reuse of `src/spc.jl` interaction model (Viewport, exact-│-follow vs. ┃-snap, drag-pan/wheel-zoom, hover tooltip, ●/◆ markers, canvas + char overlays, live/paused, gauges, side panel).
- Pure, testable functions for stats/limits/zones/WECO (separate computation from rendering).
- Keyboard-first + preserved/enhanced rich mouse (Tachikoma `MouseEvent`).
- TUI-appropriate: focused config overlays/modals (rules as keyboard-nav list/checkboxes, limits entry, spec limits), data generation + future point/CSV edit. Start with powerful single chart + extension points for multi-chart "workbench".
- Follows Elm (`@kwdef mutable struct ... <: Model`, `update!`, `view`, `should_quit`, `@tachikoma_app`).

---

## Background & Motivation

Current `src/spc.jl` (≈740 LOC) is an excellent interactive I-MR demo:
- `SPCData` + seeded `generate_spc_data` (with artificial OOC).
- `Viewport`, rich coordinate mapping (`cell_to_data_index`, `data_index_to_cell`, `nearest_point_index_to_cell_x` for snap).
- `update!` for `KeyEvent` (p/r/z/arrows) + detailed `MouseEvent` (hover, press/drag/release for pan + exact follow vs snap, wheel).
- `view`: `split_layout`, `Block`, `create_canvas` + `line!`/`dashed_line!` + `render_canvas`, char overlays (│ ┃ ● ◆), `draw_hover_tooltip!`, side panel, arc gauges, `StatusBar`.
- Live tick-driven append in `view`.
- Exhaustive TestBackend coverage in `test/test_spc.jl` (re-render-after-every-update discipline, `render_spc_visual`, PBT via Supposition, char_at for ┃/markers).

The web workbench demonstrates a **production SPC tool**:
- Verbatim WECO 1–8 (see below).
- Real data model + column mapping + subgrouping.
- Zones, spec limits, Cpk.
- Configurability and multi-chart management.

**Pain points addressed:**
- Current demo lacks WECO rules, zones, capability analysis, toggles, richer metadata.
- Web app cannot be used directly (browser, not TUI; no keyboard-first TUI model).
- Need to evolve SPC capabilities while protecting the validated demo (per CRITICAL CONSTRAINTS).

Project rules (AGENTS.md, CLAUDE.md, `.grok/docs/tachikoma-core.md`, `.grok/docs/tachikoma-ui-testing.md`) mandate:
- Read docs before UI work.
- Use `--project=.`.
- After any `src/` change affecting startup/update/view: run full `julia --project=. test/runtests.jl` + `julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'` (adapt for SPC runners/TestBackend). See also note on `.grok/rules/always-run-the-app-after-changes.md` below.
- Tiered workflow; red-first + TestBackend for UI.
- Artifact-first (this design doc).

**Note on verification rule file (Issue 2 addressed)**: The file `.grok/rules/always-run-the-app-after-changes.md` contains copy-pasted content from an unrelated QciKanban project (KanbanModel, load_users!, "No users — press [c]...", qci-kanban paths, coverage_gate.jl). It does not apply here. Follow CLAUDE.md + AGENTS.md verbatim for this repo: the two commands above (full suite + hello_tachikoma()). Per-slice verification in this design lists the exact commands. (The rule file is referenced only for general "after src/ changes" spirit; its concrete examples are ignored.)

---

## Goals & Non-Goals

**Goals (in scope for this iteration + follow-on slices):**
- Faithful port of all 8 WECO rules + zone definitions + togglable activation (defaults 1-5 ON, 6-8 OFF) with exact violation reporting.
- Support for I-MR (primary, with optional secondary MR view or toggle) and hooks for X̄-R/X̄-S.
- Auto (from data) + manual control limits; zone A/B/C lines awareness (render optional).
- Spec limits (USL/LSL/Target) + Cpk (Cpu/Cpl) display when provided.
- Keyboard-first controls + full rich mouse fidelity from `src/spc.jl` (exact │ follow on move/press/drag; ┃ snap on release using nearest screen cell; drag pan; wheel zoom; hover tooltip; persistent selection; markers).
- Workbench container model (start single powerful chart instance + clear extension points for multi-chart registry, clone, config-per-chart).
- Config UI via TUI overlays/modals: rules list (nav + toggle keys), limits/spec entry forms.
- Stats panel, violations list, rule status indicators.
- Pure computation layer (`weco_detect`, `compute_limits_and_zones`, `compute_capability`) for testability + caching.
- New public entrypoints (additive): e.g. `spc_workbench_demo()`, `advanced_spc()`.
- High test coverage: unit/PBT for rules engine (generate sequences that *must* trigger specific WECO-N), TestBackend visual/interaction tests (re-render discipline).
- Optimizations per Julia/Tachikoma practices (see below).
- Preserve exact current SPC demo behavior.

**Non-Goals (explicit boundaries):**
- **Do not modify** `src/spc.jl`, `generate_spc_data`, `SPCModel`, `static_spc_demo`, `spc_demo`, `run_*` exports, or any existing code paths/exports. (See "Keep Existing Demo Untouched" section.)
- No full web-style editable data grid (TUI space + focus; use forms or future slice for point editing/CSV).
- Not pixel-perfect recreation of HTML/CSS/JS layout or all attributes charts (p/np/c/u); prioritize I-MR + WECO + capability.
- No xlsx dependency in initial slice (use JSON/CSV or in-memory; SheetJS-equivalent future).
- No full multi-chart simultaneous visible rendering in first slice (design for it).
- Do not change Tachikoma core or add heavy deps.
- No "live" network or external tool integration.

**Quantified targets (initial):**
- Viewport support ≥200 points (current demo scale).
- WECO evaluation <1ms for n=200 on hot path.
- Full screen render on 80x24 terminal.
- TestBackend deterministic at multiple sizes (60x18, 80x20, 100x24, small 20x6 guard).

---

## Proposed Design

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ TachikomaTUI (src/TachikomaTUI.jl)                              │
│  include("spc.jl")          // UNTOUCHED                        │
│  include("spc_workbench.jl") // NEW                             │
│  export ... + new workbench symbols additively                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ src/spc_workbench.jl                                            │
│  Pure logic (testable, no Tachikoma):                           │
│    - SPCPoint, SPCSeries (or reuse/extend)                      │
│    - compute_limits, zones, weco_detect(points, cl, sigma; rules)│
│    - compute_cpk(cl, sigma, usl, lsl, target)                   │
│  Workbench model (Elm):                                         │
│    @kwdef mutable struct SPCWorkbenchModel <: Model             │
│    ... data, viewport(s), rules_enabled::Set{String},           │
│        usl/lsl/target, paused, config_mode, ...                 │
│  update!(m, KeyEvent), update!(m, MouseEvent)  // reuse patterns│
│  view(m, Frame)  // split_layout + Block + Canvas + overlays    │
│  Runners: spc_workbench_demo(), advanced_spc()                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (precompile + tests)
┌─────────────────────────────────────────────────────────────────┐
│ test/test_spc_workbench.jl (new) + updates to runtests.jl       │
│ src/precompile.jl (additive workload)                           │
└─────────────────────────────────────────────────────────────────┘
```

**Mermaid: Data Flow for Rule Evaluation (pure path)**

```mermaid
flowchart TD
    A[Raw values + metadata<br/>or generated series] --> B[compute_limits_and_zones<br/>CL = mean, sigma = std<br/>UCL/LCL = ±3σ<br/>zones: z1=1σ, z2=2σ, z3=3σ]
    B --> C{weco_detect(values, cl, sigma;<br/>enabled_rules=Set(["WECO-1",...]))}
    C -->|WECO-1| D[1 pt >3σ ?]
    C -->|WECO-2| E[window 3: count(>2σ same side)≥2]
    C -->|WECO-3..8| F[sliding windows per rule logic]
    D & E & F --> G[Vector{WECOViolation}<br/>(rule::String, index::Int, msg::String, side)]
    G --> H[Cache on (hash(values), rules_set, cl, sigma)]
    H --> I[UI: violations list + markers + stats]
    J[Spec limits USL/LSL/Target] --> K[compute_capability<br/>Cpk = min(Cpu,Cpl) or single<br/>using within sigma]
```

**Mermaid: TUI Layout (inspired by spc.jl + workbench cards)**

```mermaid
flowchart TB
    subgraph Frame
      Header["Header: title + key hints (p=paus, 1-8=rules, c=config, etc)"]
      Main[Main split: Plot | SidePanel]
      Plot["Block('SPC Workbench - I-MR') + Canvas<br/>data line, dashed UCL/LCL/mean, zone hints?, violations ticks<br/>overlays: │(hover exact), ┃(selected snap), ●/◆, horiz tick, tooltip"]
      Gauges["Gauges row (arc current + capability %)"]
      Side["Block('Stats + Rules + Violations')<br/>n, CL, UCL, LCL, σ, Cpk<br/>Rule toggles status<br/>Violations list (scrollable via keys)"]
      Footer["StatusBar: paused, last_event, mouse mode, [q]quit"]
    end
    Header --> Main
    Main --> Plot
    Main --> Side
    Plot --> Gauges
    Gauges --> Footer
```

**Mermaid: Update / View Cycle (Elm + Tachikoma)**

```mermaid
sequenceDiagram
    participant App as Tachikoma app()
    participant U as update!(m, evt)
    participant V as view(m, Frame)
    participant C as pure compute (weco/limits)

    App->>U: KeyEvent('p') or MouseEvent(...)
    U->>U: mutate (paused, viewport, hovered/selected, rules_enabled, config)
    Note over U: minimal mutation; delegate heavy to pure
    App->>V: render
    V->>V: if !paused: advance_live! (append)
    V->>C: weco_detect(cached or fresh) for current viewport slice
    V->>V: split_layout, Block, create_canvas, line!/dashed, render_canvas
    V->>V: char overlays (│ ┃ ● ◆), draw_tooltip, panels, gauges, StatusBar
    V-->>App: buffer filled
```

### Data Model Changes (New, Separate)

New structs in `src/spc_workbench.jl` (do not touch `SPCData`):

```julia
struct WECOViolation
    rule::String   # "WECO-1" .. "WECO-8"
    index::Int     # 1-based into series
    msg::String
    side::Symbol   # :above or :below or :trend etc.
end

@kwdef struct SPCSeries
    values::Vector{Float64}
    indices::Vector{Int} = collect(1:length(values))
    metadata::Vector{Dict{Symbol,Any}} = [Dict{Symbol,Any}() for _ in values]  # lot/wafer/tool/timestamp etc.
    # future: subgroup info
end

@kwdef mutable struct SPCWorkbenchModel <: Model
    quit::Bool = false
    tick::Int = 0
    series::SPCSeries
    viewport::Viewport = Viewport()  # private copy of pattern from src/spc.jl (see Key Decision #3)
    hovered::Union{Nothing,Int} = nothing
    selected::Union{Nothing,Int} = nothing
    hover_x::Union{Nothing,Int} = nothing
    paused::Bool = false
    plot_area::Rect = Rect(0,0,0,0)
    side_area::Rect = Rect(0,0,0,0)
    drag_start::Union{Nothing, NamedTuple} = nothing
    last_event::String = ""

    # Workbench / SPC specific (translated)
    cl::Float64 = 0.0
    sigma::Float64 = 1.0
    ucl::Float64 = 0.0
    lcl::Float64 = 0.0
    enabled_rules::Set{String} = Set(["WECO-1","WECO-2","WECO-3","WECO-4","WECO-5"])
    usl::Union{Float64,Nothing} = nothing
    lsl::Union{Float64,Nothing} = nothing
    target::Union{Float64,Nothing} = nothing
    cpk::Union{Float64,Nothing} = nothing
    violations::Vector{WECOViolation} = WECOViolation[]
    chart_type::String = "I-MR"  # "I-MR" | "Xbar-R" | ...
    live_max::Int = 300
    rng::MersenneTwister = Random.MersenneTwister(42)

    # UI state for TUI workbench
    config_open::Bool = false   # shows modal/overlay for rules + limits + specs
    focus_rule_idx::Int = 1     # keyboard nav in rules list
    show_secondary_mr::Bool = false
    # ... room for multi-chart list in future slice
end
```

**Keep separate from `src/spc.jl` `SPCData`/`SPCModel`.**

Data generation will be enhanced (new `generate_spc_workbench_data`) with richer metadata and OOC patterns that trigger specific WECO rules.

### Core Pure Logic (Critical — Testable First)

Translate `checkWeco` + zones/limits to pure Julia. Call this from model updates and view (cached).

```julia
# In src/spc_workbench.jl (or extracted pure file)
const WECO_RULES = [
    ("WECO-1", "1 point beyond 3σ", true),
    ("WECO-2", "2 of 3 consecutive points in zone A (beyond 2σ), same side", true),
    ("WECO-3", "4 of 5 consecutive points in zone B (beyond 1σ), same side", true),
    ("WECO-4", "8 consecutive points on the same side of CL", true),
    ("WECO-5", "6 consecutive points trending up or down", true),
    ("WECO-6", "14 consecutive points alternating up/down", false),
    ("WECO-7", "15 consecutive points within zone C (inside 1σ)", false),
    ("WECO-8", "8 consecutive points outside zone C, either side", false),
]

function compute_limits_and_zones(values::Vector{Float64})
    n = length(values)
    cl = mean(values)
    s = std(values; corrected=true)
    (cl=cl, sigma=s, ucl=cl+3s, lcl=cl-3s,
     ucl2=cl+2s, lcl2=cl-2s, ucl1=cl+s, lcl1=cl-s)
end

function weco_detect(values::Vector{Float64}, cl::Float64, sigma::Float64;
                     enabled_rules::Set{String} = Set{String}())::Vector{WECOViolation}
    # Port of checkWeco (HTML lines 2513-2593). Note: JS uses 0-based i in messages/indexes;
    # Julia uses 1-based indices (correct for 1:length(values)). Empty/sigma==0 returns [] identically.
    isempty(values) || sigma == 0 && return WECOViolation[]
    lim = (ucl3=cl+3*sigma, lcl3=cl-3*sigma, ucl2=cl+2*sigma, lcl2=cl-2*sigma,
           ucl1=cl+sigma, lcl1=cl-sigma)
    out = WECOViolation[]
    # WECO-1: 1 point beyond 3σ (HTML 2520-2526)
    if "WECO-1" in enabled_rules
        for (i,v) in enumerate(values)
            if v > lim.ucl3; push!(out, WECOViolation("WECO-1", i, "#$i = $(round(v;digits=2)) beyond +3σ (UCL $(round(lim.ucl3;digits=2)))", :above)); end
            if v < lim.lcl3; push!(out, WECOViolation("WECO-1", i, "#$i = $(round(v;digits=2)) beyond −3σ (LCL $(round(lim.lcl3;digits=2)))", :below)); end
        end
    end
    # WECO-2: 2 of 3 in zone A (>2σ) same side (HTML 2527-2535)
    if "WECO-2" in enabled_rules
        for i in 3:length(values)
            w = @view values[i-2:i]
            above = count(v -> v > lim.ucl2, w)
            below = count(v -> v < lim.lcl2, w)
            if above >= 2 || below >= 2
                push!(out, WECOViolation("WECO-2", i, "2 of 3 ending #$i in zone A (" * (above>=2 ? "+" : "−") * "2σ side)", above>=2 ? :above : :below))
            end
        end
    end
    # WECO-3: 4 of 5 in zone B (>1σ) same side (HTML 2536-2544)
    if "WECO-3" in enabled_rules
        for i in 5:length(values)
            w = @view values[i-4:i]
            above = count(v -> v > lim.ucl1, w)
            below = count(v -> v < lim.lcl1, w)
            if above >= 4 || below >= 4
                push!(out, WECOViolation("WECO-3", i, "4 of 5 ending #$i in zone B (" * (above>=4 ? "+" : "−") * "1σ side)", above>=4 ? :above : :below))
            end
        end
    end
    # WECO-4: 8 in a row same side of CL (HTML 2545-2553)
    if "WECO-4" in enabled_rules
        for i in 8:length(values)
            w = @view values[i-7:i]
            aboveAll = all(v -> v > cl, w)
            belowAll = all(v -> v < cl, w)
            if aboveAll || belowAll
                push!(out, WECOViolation("WECO-4", i, "8 in a row ending #$i" * (aboveAll ? " above" : " below") * " CL", aboveAll ? :above : :below))
            end
        end
    end
    # WECO-5: 6 in a row trending (HTML 2554-2565)
    if "WECO-5" in enabled_rules
        for i in 6:length(values)
            w = @view values[i-5:i]
            up = true; down = true
            for k in 2:length(w)
                if w[k] <= w[k-1]; up = false; end
                if w[k] >= w[k-1]; down = false; end
            end
            if up || down
                push!(out, WECOViolation("WECO-5", i, "6 in a row ending #$i" * (up ? " trending up" : " trending down"), up ? :trend_up : :trend_down))
            end
        end
    end
    # WECO-6: 14 in a row alternating (HTML 2566-2578)
    if "WECO-6" in enabled_rules
        for i in 14:length(values)
            w = @view values[i-13:i]
            alt = true
            for k in 3:length(w)
                s1 = sign(w[k-1] - w[k-2])
                s2 = sign(w[k] - w[k-1])
                if s1 == 0 || s2 == 0 || s1 == s2; alt = false; break; end
            end
            if alt
                push!(out, WECOViolation("WECO-6", i, "14 in a row ending #$i alternating up/down", :alternating))
            end
        end
    end
    # WECO-7: 15 in a row inside 1σ (HTML 2579-2585)
    if "WECO-7" in enabled_rules
        for i in 15:length(values)
            w = @view values[i-14:i]
            if all(v -> v < lim.ucl1 && v > lim.lcl1, w)
                push!(out, WECOViolation("WECO-7", i, "15 in a row ending #$i inside 1σ (over-control / stratification)", :inside))
            end
        end
    end
    # WECO-8: 8 in a row outside 1σ either side (HTML 2586-2592)
    if "WECO-8" in enabled_rules
        for i in 8:length(values)
            w = @view values[i-7:i]
            if all(v -> v > lim.ucl1 || v < lim.lcl1, w)
                push!(out, WECOViolation("WECO-8", i, "8 in a row ending #$i outside 1σ (mixture)", :outside))
            end
        end
    end
    out
end

function compute_capability(cl, sigma, usl, lsl)
    # Returns (cpk, cpu, cpl, sigma_used)
    cpu = usl !== nothing ? (usl - cl) / (3 * sigma) : nothing
    cpl = lsl !== nothing ? (cl - lsl) / (3 * sigma) : nothing
    cpk = if cpu !== nothing && cpl !== nothing; min(cpu, cpl)
          elseif cpu !== nothing; cpu
          elseif cpl !== nothing; cpl
          else nothing end
    (cpk, cpu, cpl, sigma)
end
```

**Caching:** In model, store `last_violation_key = (length, hash(values[vp_slice]), enabled_hash, cl, sigma)` and only recompute on change.

### Input Handling (Keyboard + Mouse)

Preserve/expand `src/spc.jl` patterns exactly:

- Keys: `q/esc`, `p` (pause), `r/z` (reset viewport), arrows (pan), numbers `1`–`8` (toggle WECO-N), `c` (open config overlay), `v` (focus violations), `g` (regenerate), `s` (toggle secondary), etc.
- Mouse: identical logic for `hover_x`, `compute_hovered_index`, `nearest_point_index_to_cell_x` (reuse or copy helpers into new file or share via internal), drag, wheel. Tooltip and markers enhanced with rule names on hover of viol points.
- In config mode: arrow nav + space/enter to toggle rule, number entry for limits.

`update!` for config modal must be isolated (like gate patterns).

### Rendering Strategy

- Reuse `dashed_line!`, coordinate fns, `draw_hover_tooltip!` (adapt or copy with license of pattern).
- Canvas for series + limits + optional zone bands (char fill or lines).
- Overlays for verticals, markers (◆ only on WECO violations in viewport), tooltip now shows "WECO-2 at #42".
- Side panel: current stats + Cpk (color per bands: ≥1.67 green, ≥1.33 navy, ≥1.00 amber, < red — translate from JS), enabled rules grid (compact), scrollable recent violations.
- Gauges: current value + capability gauge.
- Small terminal guard + `config_open` overlay (clear area, draw form).
- No heavy work in `view`: precompute/cache violations + limits on data change.

### Config / Builder Adaptation (TUI)

- `config_open = true` renders a centered `Block` modal (no bleed: test absence of main content under it).
- Inside: scrollable rules list (WECO-1..8 with [x] or [ ] + desc + status; keyboard nav via focus_rule_idx + arrows/space), fields for manual CL/sigma or USL/LSL/Target.
- **Tachikoma widgets (precise)**: Use `TextInput` (or `Form`/`FormField`) for numeric entry (see exploration of Tachikoma exports + hello patterns for key handling). Handle via `update!` + `if handle_key!(m.some_input, evt); return; end`. Simple key-driven fields (digits + '.' + backspace) also acceptable for minimal surface.
- "Apply" mutates model, recomputes (via weco_detect + compute_capability), closes.
- Data gen params in same or separate (seed, n, ooc patterns).
- Future slices: "builder" for column mappings, tools filter (multi-select via keys).
- **TestBackend assertions (mandatory, per .grok/docs/tachikoma-ui-testing.md "Overlay / Modal Correctness")**:
  ```
  # after update! to open config + re-render
  @test find_text(tb, "WECO-1") !== nothing && find_text(tb, "ON") !== nothing
  @test find_text(tb, "SPC Chart") === nothing || find_text(tb, "Process Data") === nothing  # no bleed of main plot
  @test find_text(tb, "USL") !== nothing
  # small terminal
  tb_small = TestBackend(20, 6); ... view ... ; @test find_text(...) || occursin("small", ...)
  ```
  Re-render after every update! before assertions. Reference tachikoma-ui-testing.md verbatim for no-bleed + drive flows only via update!.

---

## API / Interface Changes

**Additive only. No changes to existing.**

Before (unchanged):
```julia
using TachikomaTUI
static_spc_demo()  # calls app(SPCModel...) — identical
spc_demo(; paused=false)
```

After (new):
```julia
using TachikomaTUI
spc_workbench_demo()           # paused static powerful workbench
advanced_spc(; live=true)      # or spc_workbench()
# also exported: SPCWorkbenchModel, weco_detect, compute_*, generate_spc_workbench_data, ...
```

In `src/TachikomaTUI.jl` (additive):
```julia
include("spc_workbench.jl")
export SPCWorkbenchModel, spc_workbench_demo, advanced_spc, weco_detect, ...
```

Runners follow `spc.jl`:
```julia
function spc_workbench_demo(; paused::Bool = true)
    series = generate_spc_workbench_data(80; seed=42)
    m = SPCWorkbenchModel(series = series, paused=paused, ...)
    # initial compute + viewport
    app(m)
end
```

---

## Data Model Changes

- New `SPCSeries`, `WECOViolation`, `SPCWorkbenchModel` (detailed above).
- No changes to `SPCData` or existing data generator.
- Migration: none (new feature). Persistence in TUI: future (save/load JSON state via file picker overlay).
- Subgrouping: modeled in series metadata + `subgroup_size` field; I-MR is flat (subgroup=1); Xbar logic stubbed for later.

---

## Alternatives Considered

1. **Extend existing SPCModel in-place** (add WECO fields, conditional rendering).
   - Trade-off: Simpler initial code, but violates CRITICAL CONSTRAINT "DO ALL WORK SEPARATE" and "must remain fully intact". High risk of accidental behavior change to demo. Rejected.

2. **Thin wrapper around current SPC + post-processing for rules**.
   - Trade-off: Code reuse high, but Viewport/mouse/ live logic duplication hard to avoid; violates clean separation; WECO needs its own series/limits model anyway. Rejected for long-term maintainability.

3. **Pure separate pure-SPC package + TUI shell** (future ideal).
   - Trade-off: Best for testability/reuse, but out of scope for this TUI project iteration (adds repo complexity). Current proposal keeps logic inside `spc_workbench.jl` (pure fns first 30-40%) as pragmatic middle. Selected.

4. **Full web parity with data table editing**.
   - Rejected: TUI space/keyboard philosophy; current spc interaction model is the north star.

---

## Security & Privacy Considerations

- No auth or external data in initial design (in-memory only).
- File I/O (future CSV/JSON save): use safe paths, no `..` traversal; respect `.grok/hooks/safety.py`.
- Seeded RNG for demos (deterministic, no secrets).
- Imported data (future): treat as untrusted; validate numeric columns only; no code eval.
- Threat model: local TUI only — primary risk is UI state corruption (mitigated by pure compute + tests).

---

## Observability

- `last_event` + tick already present; extend with "violations=$(length(m.violations)) rules=$(length(enabled))".
- In tests: assert on violation counts after specific key sequences.
- No metrics/alerting (local app); logging via `println` guarded or future Tachikoma hooks.
- Precompile workload will exercise rule paths.

---

## Rollout Plan

- **Design phase (this doc)** → user review.
- Slice 1 (Tier-1): pure logic + tests (weco_detect PBT + unit) + basic model + static render (no mouse yet) + **explicit edit to wire `test/test_spc_workbench.jl` (and note on existing test_spc.jl) into runtests.jl**. New files + additive edit only. See PR Plan for exact include.
- Slice 2: port rich mouse/keyboard + viewport from spc patterns + TestBackend visuals.
- Slice 3: config overlay + rule toggles + Cpk + spec limits.
- Slice 4: live, gauges, violations panel polish + precompile + exports.
- Slice 5 (optional): secondary MR view, basic multi-chart list, data gen enhancements.
- Feature flag: none needed (new runners).
- Rollback: git revert of new files only; existing demo untouched.
- **Standardized verification per slice** (addresses Issues 1-3; use these exact commands after any src/ or test/ change):
  ```
  julia --project=. test/runtests.jl   # must exercise new tests (after include edit)
  julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
  julia --project=. -e 'using TachikomaTUI; m = ...; using Tachikoma as T; tb=T.TestBackend(80,20); ... update! + re-render + find_text/char_at assertions'  # headless for workbench
  # (git diff review of only new/additive files)
  ```
  Note: `.grok/rules/always-run-the-app-after-changes.md` is QciKanban-oriented and ignored; use CLAUDE.md/AGENTS.md commands above. Current project state: only hello is wired in runtests.jl (SPC tests run via direct include); this work will add the include(s) as side-effect.

After **any** `src/` or test/ edit affecting models/update/view: mandatory re-run of the standardized commands above + evidence (stdout + exit codes).

---

## Risks & Mitigations

(Addresses Issue 5; consolidated from scattered notes.)

- **Risk (high severity)**: Off-by-one or windowing errors in WECO-3/5/6/7/8 port (e.g., slice bounds, strict vs non-strict comparisons, sign(0) handling). HTML JS (lines 2537-2592) is the spec. Mitigation: red-first PBT in slice 1 with generators that *force* exact trigger sequences (e.g., 4/5 points > ucl1 same side for WECO-3; 15 strictly inside for WECO-7; alternating with no zeros); cross-check outputs vs manual enumeration + TestBackend char_at on markers for known viol indices. Use `@view` and `enumerate` (1-based) explicitly.
- **Risk (medium)**: Viewport + coordinate helpers duplication (data_index_to_cell etc.) leads to drift vs src/spc.jl over time. Mitigation: Document as private (non-exported) copies inside spc_workbench.jl only; plan optional later internal common (but never touch src/spc.jl). Tiny size (Viewport is 4 fields) keeps cost low.
- **Risk (medium)**: Config modal + text input for limits/specs has edge cases on small terminals or bleed; TextInput/Form handling subtle. Mitigation: Follow `.grok/docs/tachikoma-ui-testing.md` "Overlay / Modal Correctness" ("Board ... content must not appear under the overlay"); use TestBackend at 20x6 + 80x18; assert `find_text` for rule list items + `!find_text` (or scoped) for main plot content under overlay. Small-terminal guard first in view.
- **Risk (low)**: Live append + full WECO on n=300+ with many enabled rules + Cpk may allocate or slow hot path in view. Mitigation: Pure functions + cache key (length + hash(slice) + rules hash + cl/sigma) before calling weco_detect in view; prealloc series vectors; move any heavy to update! on data change only. Quant target <1ms WECO for n=200.
- **Assumption**: Separation constraint is non-negotiable; no shared internal modules between spc.jl and workbench in v1.

---

## Open Questions

1. Exact public runner names: `spc_workbench_demo()` vs `advanced_spc()` vs `workbench_spc()`? (Recommend `spc_workbench_demo()` + `spc_workbench()` for live.)
2. (Resolved per Issue 7 + Key Decision #3): Duplicate Viewport + 4-5 coordinate helpers privately inside spc_workbench.jl (non-exported). Pure WECO fns exported early (from defining slice) for testability.
3. Level of subgroup support in slice 1 vs later (I-MR is sufficient for WECO fidelity)?
4. Include basic CSV import in initial workbench or strictly future?
5. Color/Style mapping for Cpk bands — reuse project palette or define new?

---

## References

- HTML workbench: `spc-html-mocup/SPC_workbench_2026-06-18-20-46.html` (WECO table lines ~925-932, rules JS ~1055-1062, checkWeco ~2513-2593, computeChart ~2226+, builder ~580+, data JSON ~1048, Cpk bands ~2610).
- Current template: `src/spc.jl` (full: Viewport ~40, mouse logic ~380-430, dashed_line ~300, draw_tooltip ~230, render ~460, runners ~700).
- Tests: `test/test_spc.jl` (render_spc_visual ~25, selected ┃ test ~140-190, PBT ~340, re-render discipline everywhere); `test/runtests.jl` (currently only `include("test_hello.jl")`; this design adds explicit `include("test_spc_workbench.jl")` + note on wiring SPC tests).
- Core docs: `.grok/docs/tachikoma-core.md`, `.grok/docs/tachikoma-ui-testing.md` (TestBackend pattern, re-render, no-bleed, small terminal).
- AGENTS.md (Tier 2 design + PR plan DAG, mandatory run-the-app, Julia rules).
- Project: `src/TachikomaTUI.jl`, `src/precompile.jl`, `Project.toml` (deps: Tachikoma, PrecompileTools, Statistics, Random, Supposition, JSON).
- WECO verbatim from workbench (quoted in Overview + Proposed Design).
- Tachikoma patterns: `@tachikoma_app`, `Block`+`render`, `create_canvas`/`line!`/`set_point!`, `split_layout(Layout(Vertical/Horizontal, [Fixed, Fill]))`, `StatusBar`, `char_at`/`find_text` assertions.

---

## Key Decisions

1. **Strict separation via new files + additive exports only** — Directly satisfies CRITICAL CONSTRAINTS and "use existing SPC as strong technical template" without risk of mutation. Rationale: protects validated demo + allows independent evolution.
2. **Pure functions for WECO/limits/cpk first** (weco_detect etc. with no side effects) — Enables PBT, unit tests independent of UI, caching, and future extraction. Julia best practice + matches "pure functions for stats/rules (testable)" research note. (Full bodies for WECO-3..8 now provided with HTML citations.)
3. **Copy/adapt interaction primitives** (nearest snap, exact hover_x, tooltip drawing, coordinate fns) rather than shared module in v1 — Avoids touching `src/spc.jl`. Later refactor opportunity. **Guidance (Issue 7)**: Duplicate the ~4-5 tiny Viewport + coordinate helpers (data_index_to_cell, nearest_point_index_to_cell_x, etc.) inside `src/spc_workbench.jl` as *private* (no `export`, not using `using ...: Viewport`). Keep them non-public.
4. **Single powerful chart + extension points** for workbench (vs immediate multi-card) — Matches "start with single... + easy extension", keeps TUI layout tractable on 80-col, reduces scope.
5. **TestBackend + re-render-after-every-update! + Supposition PBT** as non-negotiable — Per `.grok/docs/*` and existing `test_spc.jl`. Specific: PBT generators that force WECO-2/5/7 triggers.
6. **Keyboard primary (dedicated keys for 1-8 rules, c for config) + full mouse parity** — Preserves "philosophy of keyboard first but rich TUI mouse functionality".
7. **No change to pre-existing public API surface of SPC** — Runners and types stay exactly as exported today. **Export timing (Issue 7 resolved)**: Export pure WECO fns (`weco_detect`, `compute_*`) from the slice that first defines them (slice 1, even if via internal re-export or qualified use in tests initially). Public API addition in TachikomaTUI.jl can be minimal early; full runners/exports in slice 7. This allows pure tests without waiting for UI.

---

## PR Plan (DAG of Independently Mergeable Slices)

All slices are Tier-1 (lead implements + tests in context). Each includes:
- New file(s) only or additive edits (explicitly including the `test/runtests.jl` include for the new test file to make "full suite" gates meaningful).
- Full `julia --project=. test/runtests.jl` (exit 0) + app verification (standardized exact commands per slice above).
- TestBackend + PBT where applicable.
- Evidence capture.

**DAG (topological order; arrows = "depends on")**:

```
pure-logic + test-wiring (1)
   |
   +--> model-render-core (2) --> mouse-keyboard (3)
                  |                    |
                  +--> config-overlay (4) --> full-stats-cpk-viol (5)
                                             |
                                             +--> live-gauges-precomp (6)
                                                              |
                                                              +--> docs+export+demo-runner (7)
```

**Detailed slices:**

1. **"Add pure WECO + stats functions + generator + wire tests into runtests.jl (no UI)"**
   - Files: `src/spc_workbench.jl` (new, pure section only), `test/test_spc_workbench.jl` (new, unit + PBT), `test/runtests.jl` (additive: add `include("test_spc_workbench.jl")`; also optionally wire existing `test_spc.jl` for completeness — note current state only includes hello).
   - Deps: none.
   - Desc: Implement `weco_detect` (full port), `compute_limits_and_zones`, `compute_capability`, `generate_spc_workbench_data` (richer data, OOC that hits rules). 100% unit/PBT coverage. Red-first: tests that assert exact violations for crafted sequences (e.g. 2/3 in zone A). No Tachikoma dep in this logic. **Critical**: the include edit ensures "full suite" gates actually run the new (and existing SPC) code.
   - Verification (standardized):
     ```
     julia --project=. test/runtests.jl   # now includes new workbench tests
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     julia --project=. -e 'using TachikomaTUI; ... weco_detect directly or via include ...'  # pure tests
     ```

2. **"SPCWorkbenchModel skeleton + static render (paused)"**
   - Files: `src/spc_workbench.jl` (add model + view basics), additive to `test/test_spc_workbench.jl`.
   - Deps: 1.
   - Desc: `@kwdef mutable struct ...`, `should_quit`, basic `view` (header, split, canvas line + limits, side stats stub), `Viewport` helpers (copy patterns), `render_spc_workbench_visual` test helper. Use paused static data.
   - Gate (standardized):
     ```
     julia --project=. test/runtests.jl
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     # + headless TestBackend for workbench model
     ```

3. **"Rich mouse + keyboard interactions (exact fidelity to spc.jl)"**
   - Files: `src/spc_workbench.jl` (update! Key+Mouse, coordinate fns, tooltip, markers).
   - Deps: 2.
   - Desc: Port `compute_hovered_index`, `nearest_point..._to_cell_x`, hover_x vs selected, drag pan, wheel, │ vs ┃, ●/◆ (now viol-aware), key handlers (p/r + new 1-8, c). Test selected ┃ persistence while hovering (char_at assertions).
   - Gate (standardized):
     ```
     julia --project=. test/runtests.jl
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     ```

4. **"Config overlay + rule toggles"**
   - Files: `src/spc_workbench.jl` (config_open state + view branch + update handling).
   - Deps: 3.
   - Desc: Modal that does not bleed (test absence of plot text under it), keyboard nav for rules list, toggle via space/1-8 even in overlay, apply recomputes via weco_detect.
   - Gate (standardized):
     ```
     julia --project=. test/runtests.jl
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     ```

5. **"Capability (Cpk), spec limits, violations list, zones"**
   - Files: `src/spc_workbench.jl`.
   - Deps: 4.
   - Desc: usl/lsl/target fields + form entry, compute + display (colors), violations panel (list top N), zone lines or indicators. Update side panel + tooltip.
   - Gate (standardized):
     ```
     julia --project=. test/runtests.jl
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     ```

6. **"Live mode, gauges, polish + precompile"**
   - Files: `src/spc_workbench.jl`, `src/precompile.jl` (additive workload for new model + interactions), `test/...`.
   - Deps: 5.
   - Desc: `advance_live!` adapted (respect rules recalc), arc gauges (current + cpk), StatusBar, viewport follow. Add to `@compile_workload`.
   - Gate (standardized):
     ```
     julia --project=. test/runtests.jl
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     ```

7. **"Public runners, exports, integration, final gates"**
   - Files: `src/TachikomaTUI.jl` (additive include + export), `src/spc_workbench.jl` (runners), README if needed (doc), full test run.
   - Deps: 6.
   - Desc: `spc_workbench_demo()`, `advanced_spc()`, ensure `using TachikomaTUI; TachikomaTUI.hello_tachikoma()` still works + new runners callable. Full suite green (now including workbench tests via prior include). Run live app verification. Capture evidence.
   - Gate (standardized + final evidence):
     ```
     julia --project=. test/runtests.jl
     julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'
     julia --project=. -e 'using TachikomaTUI: spc_workbench_demo; ...'  # or record_app
     # git diff (new files + additive only; no src/spc.jl changes)
     ```

Optional later (after base lands):
- Multi-chart workbench container.
- CSV import + point edit form.
- X̄-R / X̄-S full + subgroup binning.
- Persistence (JSON state).

Each slice produces mergeable PR with title like "feat(spc-workbench): pure WECO detector + PBT + test wiring (slice 1/7)".

---

*End of design document. All claims cite concrete files, lines, and verbatim workbench content from tool-assisted analysis. Issues 1-7 from review addressed (see review_file responses). Key Decisions and PR Plan updated.*
