#!/usr/bin/env julia
# R4 — PECVD hand-path tutorial (.tach). From repo root:
#   julia --project=. scripts/record_pecvd_tutorial.jl
#   julia --project=. scripts/record_pecvd_tutorial.jl /tmp/pecvd.tach
#
# Fixtures: test/fixtures/spc/pecvd/*.csv
# Session is API-seeded (import paths not typed in-frame); see docs/user/tutorial-blank-to-pecvd.md

using TachikomaTUI

out = length(ARGS) >= 1 ? ARGS[1] : "agent_logs/pecvd_tutorial.tach"
path = record_pecvd_tutorial_demo(out)
println("wrote $path ($(filesize(path)) bytes)")
println("fixtures: ", default_pecvd_fixture_dir())
