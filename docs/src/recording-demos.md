# Recording demos

Tachikoma.jl can **capture terminal frames** to a native `.tach` file (and
export GIF/SVG from that). This project starts documentation with one **trivial**
recording so the pipeline is proven before we capture the full SPC workbench.

Upstream detail: [Tachikoma recording docs](https://kahliburke.github.io/Tachikoma.jl/dev/recording/).

---

## Why start small?

| Goal | Why Hello first |
|------|-----------------|
| Prove `record_app` works in *this* package | One model, few keys, no live ticks |
| Document the pattern once | Same API for workbench later |
| Keep CI / scripts fast | ~45 frames, tiny `.tach` |
| Avoid coupling docs to WECO/IO flux | Workbench captures are a later slice |

---

## Interactive capture (any running app)

While an app is running in a real terminal:

1. **Ctrl+R** — start (5 s countdown)
2. Use the app normally
3. **Ctrl+R** — stop → writes `tachikoma_….tach` and opens export modal (GIF/SVG)

Useful for ad-hoc walkthroughs. Prefer **scripted** `record_app` for docs that
must stay deterministic.

---

## Trivial scripted demo: Hello counter

### What it records

`record_hello_demo` drives `HelloModel` headlessly:

| Frame (approx.) | Key | Effect |
|-----------------|-----|--------|
| 5 | space | count → 1 |
| 10 | `+` | count → 2 |
| 15 | ↑ | count → 3 |
| 22 | `r` | reset → 0 |
| 28 | `+` | count → 1 |
| 40 | Esc | quit (capture ends) |

### Run it

```bash
# From repo root
julia --project=. scripts/record_hello_demo.jl
# → agent_logs/hello_demo.tach

julia --project=. scripts/record_hello_demo.jl /tmp/hello_demo.tach
```

Or from Julia:

```julia
using TachikomaTUI
record_hello_demo("agent_logs/hello_demo.tach")
```

Launch the live app (not a recording):

```julia
using TachikomaTUI
hello_tachikoma()   # space / + / ↑ increment, r reset, q/Esc quit
```

### Inspect the `.tach`

```julia
using Tachikoma
w, h, cells, timestamps, pixels = load_tach("agent_logs/hello_demo.tach")
length(cells)   # number of frames
(w, h)          # terminal size used for capture
```

GIF export needs Tachikoma’s GIF extension (`enable_gif()` + FreeType/ColorTypes).
SVG export does not require those packages. See upstream recording docs.

### Note on git

This repo’s `.gitignore` includes `*.tach` so large captures are not committed by
default. Regenerate demos with the script when needed; commit the *generator*
and docs, not the binary unless you deliberately opt in.

---

## Pattern to copy for the next demo

```julia
using Tachikoma
using TachikomaTUI: SomeModel   # or construct your model

m = SomeModel(...)
events = [
    (10, KeyEvent('m')),      # open library, etc.
    (20, KeyEvent(:escape)),
]
record_app(m, "demo.tach"; width=100, height=30, frames=90, fps=10, events=events)
```

Rules of thumb:

1. Prefer **paused** / non-live models for deterministic frames.
2. Number events by **capture frame** (after any `warmup`).
3. Keep width/height fixed in the doc so screenshots match.
4. End with Esc/q only if `should_quit` should stop early (Hello does).

---

## Tutorial path recordings (R3–R5)

Blank slate, PECVD CSV hand-path, and `:fake_tool` PARAMS are documented on
[Tutorial path](@ref) and under `docs/user/tutorial-*.md`.

```bash
julia --project=. scripts/record_tutorial_path.jl
```

| Function | Script |
|----------|--------|
| `record_blank_workbench_demo` | `scripts/record_blank_workbench.jl` |
| `record_pecvd_tutorial_demo` | `scripts/record_pecvd_tutorial.jl` |
| `record_fake_tool_tutorial_demo` | `scripts/record_fake_tool_tutorial.jl` |

## What this page is *not* yet

- Animated GIF assets checked into Documenter (R1)  

See repository `docs/design/recording-docs-plan.md`.
