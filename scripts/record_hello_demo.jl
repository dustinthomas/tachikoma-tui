#!/usr/bin/env julia
# Trivial headless recording demo (Hello counter).
#
# From repo root:
#   julia --project=. scripts/record_hello_demo.jl
#   julia --project=. scripts/record_hello_demo.jl path/to/out.tach
#
# Output is a Tachikoma `.tach` file (gitignored by default via `*.tach`).
# Interactive alternative while any app is running: Ctrl+R start/stop.

using TachikomaTUI

out = length(ARGS) >= 1 ? ARGS[1] : "agent_logs/hello_demo.tach"
path = record_hello_demo(out)
println("wrote $path ($(filesize(path)) bytes)")
println("reload: using Tachikoma; load_tach(\"$path\")")
