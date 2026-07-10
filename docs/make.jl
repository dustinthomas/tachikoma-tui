# Documenter build entry (scaffold — full green is PR11, not PR0).
#
# Optional instantiate:
#   julia --project=docs -e 'using Pkg; Pkg.instantiate()'
#   # fallback: Pkg.develop(path="..") if [sources] path dep is unavailable
# Build (later):
#   julia --project=docs docs/make.jl

using Documenter
using TachikomaTUI

makedocs(;
    modules = [TachikomaTUI],
    authors = "Grok Agentic Experiments",
    sitename = "TachikomaTUI",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = nothing,
        edit_link = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "SPC Workbench" => "spc-workbench.md",
        "API" => "api.md",
    ],
    checkdocs = :none,
    warnonly = true,
)
