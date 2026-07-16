#!/usr/bin/env julia
# Run R3 + R4 + R5 tutorial recordings. From repo root:
#   julia --project=. scripts/record_tutorial_path.jl

using TachikomaTUI

mkpath("agent_logs")
b = record_blank_workbench_demo("agent_logs/blank_workbench.tach")
p = record_pecvd_tutorial_demo("agent_logs/pecvd_tutorial.tach")
f = record_fake_tool_tutorial_demo("agent_logs/fake_tool_tutorial.tach")
println("R3 blank:      $b ($(filesize(b)) bytes)")
println("R4 pecvd:      $p ($(filesize(p)) bytes)")
println("R5 fake_tool:  $f ($(filesize(f)) bytes)")
