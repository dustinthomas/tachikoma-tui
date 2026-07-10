# Documenter build entry (scaffold — full green is PR11, not PR0).
#
# Optional instantiate:
#   julia --project=docs -e 'using Pkg; Pkg.develop(path=".."); Pkg.instantiate()'
# Build (later):
#   julia --project=docs docs/make.jl

using Pkg
Pkg.develop(PackageSpec(; path = dirname(@__DIR__)))

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
    ],
    checkdocs = :none,
    warnonly = true,
)
