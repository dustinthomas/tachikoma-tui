#!/usr/bin/env julia
# R3 — blank workbench (.tach). From repo root:
#   julia --project=. scripts/record_blank_workbench.jl
#   julia --project=. scripts/record_blank_workbench.jl /tmp/blank.tach

using TachikomaTUI

out = length(ARGS) >= 1 ? ARGS[1] : "agent_logs/blank_workbench.tach"
path = record_blank_workbench_demo(out)
println("wrote $path ($(filesize(path)) bytes)")
println("live blank: julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:none)'")
