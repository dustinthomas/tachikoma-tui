# CLAUDE.md — tachikoma-tui

Julia + Tachikoma.jl TUI project. Uses the Grok agentic workflow defined in AGENTS.md and `.grok/`.

## Key Commands
- `julia --project=. test/runtests.jl`
- `julia --project=. -e 'using TachikomaTUI; TachikomaTUI.hello_tachikoma()'`

See AGENTS.md for the Tiered Workflow, verification gates, and Tachikoma rules.

This workspace is set up with:
- `.grok/` — config, validator persona, skills (prime, review, test, tdd, commit, caveman), safety hooks, docs
- Full support for single-agent + independent verifier pattern

Replicated agentic setup 2026-07.
