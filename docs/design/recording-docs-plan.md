# Plan: documentation + terminal recordings

**Status:** R0 + R3 + R4 + **R5 fake_tool PARAMS** shipped  
**Goal:** grow operator- and developer-facing docs with deterministic screen captures, without blocking product work.

---

## Done

| Item | Location |
|------|----------|
| R0 Hello recorder | `record_hello_demo` · `scripts/record_hello_demo.jl` |
| R3 blank workbench | `record_blank_workbench_demo` · `scripts/record_blank_workbench.jl` |
| R4 PECVD hand path | `make_pecvd_tutorial_workbench` · `record_pecvd_tutorial_demo` · `scripts/record_pecvd_tutorial.jl` |
| R5 fake_tool PARAMS | `make_fake_tool_workbench` · `record_fake_tool_tutorial_demo` · `scripts/record_fake_tool_tutorial.jl` |
| Tutorial operator guides | `docs/user/tutorial-blank-to-pecvd.md`, `tutorial-fake-tool-params.md` |
| Documenter | `docs/src/tutorial.md`, `recording-demos.md` |
| All tutorial captures | `scripts/record_tutorial_path.jl` |
| Local browser docs | `open_local_docs` · help/keymap **O** · `scripts/open_docs.jl` |
| Tests | `test/test_hello.jl`, `test/test_recording_tutorial.jl`, `test/test_local_docs.jl` |

---

## Principles

1. **Script first, film later** — every doc capture is a Julia `record_app` script with fixed size/fps/events.
2. **One vertical slice per PR** — one app surface + one doc page + one test, not a mega recording suite.
3. **Determinism** — `paused=true`, fixed RNG seeds, no wall-clock live ticks in recorded demos.
4. **Generators in git; binaries optional** — keep `*.tach` gitignored unless a small asset is deliberately vendored.
5. **Hello proves the pipe** — workbench only after Hello recording stays green in CI/local gates.

---

## Proposed DAG (small PRs)

```text
[done] R0 Hello record_hello_demo + docs page
   │
   ├─► R1 Documenter assets pipeline (optional GIF/SVG from .tach)
   │
   ├─► R2 Classic SPC single-chart record (static_spc / paused)
   │
   ├─► [done] R3 Workbench blank slate (:none)
   │
   ├─► [done] R4 Workbench PECVD hand path (API seed + nav recording)
   │
   ├─► [done] R5 Workbench :fake_tool PARAMS walkthrough (; j + compare)
   │
   └─► [done] R6 Operator tutorial pages (blank/CSV + fake_tool)
```

### R1 — Assets pipeline (optional)

- Script: load `.tach` → export SVG (no extra deps) and/or GIF if `enable_gif()`.
- Wire Documenter to embed a static first-frame or SVG when present.
- Skip hard CI fail if font/GIF deps missing (warn-only).

### R2 — Classic SPC

- `record_spc_demo` with paused model + 2–3 keys (pan, rule toggle if safe).
- Doc subsection under recording-demos or `spc-workbench` sibling page.

### R3 — Blank workbench

- `spc_workbench_demo(seed_demos=:none)` path recorded headlessly.
- Events: `?` or `k`, Esc back — proves chrome without data.

### R4 — PECVD load tutorial (hand path)

- Use `test/fixtures/spc/pecvd/*.csv`.
- Scripted: library `m` → import path is awkward as pure keys (path prompt).  
  **Prefer:** construct model via `import_csv_new_chart!` / API in the recorder, then record **navigation** (library, builder, specs) rather than typing full paths in-frame.
- Doc: step list matching `docs/user/` tone + “what you should see.”

### R5 — fake_tool product walkthrough

- `seed_demos=:fake_tool`, paused.
- Events: `;`, `j`, `,`, `=` for PARAMS / compare chips.
- Shortest high-value product demo for stakeholders.

### R6 — Tutorial assembly

- Single “Learning path” page: blank → import → fake_tool vs hand CSV.
- Links only; no new recording logic.

---

## Non-goals (for now)

- Full session video of every workbench key  
- Replacing TestBackend unit tests with recordings  
- Auto-upload of captures to external hosts  

---

## Verification per slice

1. `julia --project=. test/runtests.jl` (or targeted test file)  
2. Recording script exits 0; `load_tach` frame count ≥ 1  
3. `julia --project=docs docs/make.jl` exit 0 when docs pages change  
4. After `src/` changes that affect runners: smoke `hello_tachikoma` or workbench demo as today  

---

## Open decisions

| ID | Question | Default proposal |
|----|----------|------------------|
| OD-1 | Commit small `.svg` exports? | Yes if &lt; ~100 KB; keep `.tach` ignored |
| OD-2 | Workbench path typing in recorder? | Prefer API seed + key navigation |
| OD-3 | GIF in CI? | Optional job; not required for green gate |

---

## Immediate next step after seed

Pick **R3** (blank workbench chrome) or **R5** (`:fake_tool` product) depending on audience:

- **Developers / pipeline** → R3 then R4  
- **Product demo** → R5 first, then R4 hand-import story
