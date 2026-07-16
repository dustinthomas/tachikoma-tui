#!/usr/bin/env julia
# Open local Documenter HTML in the default browser.
#
#   julia --project=. scripts/open_docs.jl
#   julia --project=. scripts/open_docs.jl tutorial
#   julia --project=. scripts/open_docs.jl spc-workbench
#
# Prebuilt docs/build is in git. Rebuild after docs/src edits:
#   julia --project=docs docs/make.jl

using TachikomaTUI

page = length(ARGS) >= 1 ? ARGS[1] : "index.html"
msg = open_local_docs(; page = page)
println(msg)
if startswith(msg, "docs not built")
    exit(1)
end
