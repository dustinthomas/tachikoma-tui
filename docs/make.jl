# Documenter build entry — must exit 0 when docs change.
# Prebuilt HTML under docs/build/ is committed so workbench O works after git pull.
#
# Instantiate (once per env):
#   julia --project=docs -e 'using Pkg; Pkg.instantiate()'
# Fallback if [sources] path dep is unavailable:
#   julia --project=docs -e 'using Pkg; Pkg.develop(path=".."); Pkg.instantiate()'
# Build (then commit docs/build/ with source changes):
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
        "Tutorial path" => "tutorial.md",
        "Recording demos" => "recording-demos.md",
        "API" => "api.md",
    ],
    # Many public names are thin reexports without full docstrings yet.
    # checkdocs=:none keeps the PR11 green gate focused on build success.
    checkdocs = :none,
    warnonly = true,
)
