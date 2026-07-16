#!/usr/bin/env julia
# R5 — :fake_tool PARAMS / Compare tutorial (.tach). From repo root:
#   julia --project=. scripts/record_fake_tool_tutorial.jl
#   julia --project=. scripts/record_fake_tool_tutorial.jl /tmp/fake_tool.tach

using TachikomaTUI

out = length(ARGS) >= 1 ? ARGS[1] : "agent_logs/fake_tool_tutorial.tach"
path = record_fake_tool_tutorial_demo(out)
println("wrote $path ($(filesize(path)) bytes)")
println("live: julia --project=. -e 'using TachikomaTUI; TachikomaTUI.spc_workbench_demo(seed_demos=:fake_tool)'")
