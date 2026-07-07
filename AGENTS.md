# AGENTS.md (Grok project rules)

Project: **tachikoma-tui** — New Julia + Tachikoma.jl TUI project.

**Workflow policy (2026-07 revision):** see `.grok/docs/agentic-workflow-2026-07.md` for the full rationale and verified evidence. Summary: single agent by default, context-centric decomposition, one independent verifier, no role-play pipelines. The old `/pipeline` persona pipeline and 3-agent `/tdd` choreography are **deprecated**; their personas and docs were removed 2026-07-05 (see git history), only the redirecting `/pipeline` tombstone remains.

**MANDATORY RULE:**
After ANY change to src/ that affects startup, update!/view, or the main app:
- Run a real app verification: `julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'`
- For headless/deterministic checks use the TestBackend tests.
- Save evidence. Never finish without verifying the app runs.

## Tiered Workflow (the default process)

Work is tiered by size. The lead does the work itself in one context; **the agent that implements a feature also writes its tests**. Never split plan/code/test across separate agents by role — every handoff loses context.

**Tier 0 — trivial** (typo, label, one-line guard): direct edit + the targeted tests. No subagents.

**Tier 1 — normal feature/bugfix (default):**
1. *Scout (optional)*: if broad codebase context is needed, spawn ONE read-only explore subagent that returns a condensed summary (~1–2k tokens, file:line + short snippets). Don't fold file dumps into the lead context. If you already know the files, just read them.
2. *Plan inline*: short written plan (plan.md for larger work). No separate planner agent.
3. *Implement + test in the same context*: write the change AND its tests yourself — red-first for behavioral changes. Consult test files and run targeted tests as you go, then the full suite.
4. *Verify independently*: spawn ONE verifier subagent (validator persona) with the task description + changed-file list and **explicit criteria**: run the complete test suite (`julia --project=. test/runtests.jl`), run the app, review the actual `git diff` from disk. Verdict APPROVED only on full-suite green + zero critical findings. Fix findings, re-verify (use `resume_from`).

**Tier 2 — large multi-part work:** `/design`-style short design doc with a PR plan (DAG of small slices) → user buy-in → each slice as Tier-1. Use `isolation: "worktree"` for parallel slices.

For medium tasks the bundled `/implement` is an acceptable Tier-1 variant.

## TDD (revised)

Red-first is a *discipline inside the single agent*: for behavioral changes, write the failing test first, watch it fail, make it pass minimally, then refactor. Use the TestBackend heavily for UI.

## Verification culture (non-negotiable, any tier)

- Never claim green without running the commands yourself in this session; exact command + exit_code.
- Re-audit "all pass" claims.
- After `src/` changes: full suite + app run (at minimum the hello runner or your main entry).
- Reviewer/verifier findings quote code verbatim from disk.
- "No test needed" requires explicit written justification.

## Token discipline

- Artifact-first: durable state goes to disk (plan.md, `agent_logs/<slug>/`).
- Prefer `git diff` and targeted excerpts over whole-file dumps.
- Subagents for context isolation (exploration, verification) — depth limit = 1.

## Model Assignment

- **Lead / verifier**: `grok-build`
- **Scout / explore subagents**: `grok-composer-2.5-fast`
- Routing lives in `.grok/config.toml` (`[subagents.models]`) and persona `model =` lines.

## Julia + Tachikoma Specific Rules

**Before substantial Tachikoma UI work** (new views, modals, focus/keymap changes), read the docs in `.grok/docs/` (tachikoma-core.md, tachikoma-ui-testing.md).

- Always invoke Julia with `julia --project=.`.
- Tachikoma apps follow Elm: `mutable struct X <: Model`, `should_quit`, `update!(m, KeyEvent)`, `view(m, Frame)`. Use `@tachikoma_app`.
- UI verification is headless and deterministic: `Tachikoma.TestBackend` + `find_text`/`row_text`/`char_at` + **re-render after every `update!`** before asserting.
- Drive flows exclusively through `update!(m, KeyEvent(...))`.
- Full suite: `julia --project=. test/runtests.jl`
- Use `record_app` / `record_widget` when available for visual demos.

## Skills

- `/tdd`, `/review`, `/test`, `/commit`, `/prime`, `/caveman`
- Bundled: `/implement`, `/design`, `/execute-plan`

## Hooks

- One agent hook: `.grok/hooks/safety.py` — blocks catastrophic `rm -rf` and `.env*` access.

## Conventions

- Keep skills focused and version-controllable.
- Keep this file under 200 lines.
- When workflow policy changes, update `.grok/` together.

---

Replicated from julia-tachikoma-ui-test for a clean new Tachikoma.jl TUI project (2026-07).
