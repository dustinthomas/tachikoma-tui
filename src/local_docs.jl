# ═══════════════════════════════════════════════════════════════════════
# Local Documenter HTML — open in system browser (private / offline app)
#
# Build once:
#   julia --project=docs docs/make.jl
# Then from the workbench: h → o   or  open_local_docs()
# ═══════════════════════════════════════════════════════════════════════

"""Package root (directory containing `src/` and `docs/`)."""
package_root() = dirname(@__DIR__)

"""Documenter output directory: `docs/build/`."""
local_docs_build_dir() = joinpath(package_root(), "docs", "build")

"""
    resolve_local_docs_file(page="index.html") -> String | nothing

Absolute path to a built HTML page under `docs/build/`, or `nothing` if missing.
`page` may be `"index"`, `"index.html"`, `"tutorial"`, etc. Path traversal is
rejected (basename only).
"""
function resolve_local_docs_file(page::AbstractString = "index.html")::Union{String,Nothing}
    base = basename(String(page))
    isempty(base) && return nothing
    if !endswith(lowercase(base), ".html") && !endswith(lowercase(base), ".htm")
        base = base * ".html"
    end
    path = joinpath(local_docs_build_dir(), base)
    return isfile(path) ? abspath(path) : nothing
end

"""`file://` URL for a local filesystem path (cross-platform)."""
function file_url(path::AbstractString)::String
    ap = abspath(path)
    if Sys.iswindows()
        # file:///C:/Users/...
        return "file:///" * replace(ap, '\\' => '/')
    end
    return "file://" * ap
end

"""
    open_in_browser(path_or_url; dry_run=false) -> Union{Nothing,String}

Open a local path or URL in the default browser. Returns `nothing` on success
(or when `dry_run=true`), else an error message string.
"""
function open_in_browser(path_or_url::AbstractString; dry_run::Bool = false)::Union{Nothing,String}
    target = String(path_or_url)
    url = if startswith(target, "http://") || startswith(target, "https://") ||
             startswith(target, "file:")
        target
    else
        isfile(target) || return "not found: $target"
        file_url(target)
    end
    dry_run && return nothing
    try
        if Sys.isapple()
            run(Cmd(`open $url`); wait = false)
        elseif Sys.iswindows()
            # empty title arg required by `start`
            run(Cmd(`cmd /c start "" $url`); wait = false)
        else
            xdg = Sys.which("xdg-open")
            if xdg !== nothing
                run(Cmd(`$xdg $url`); wait = false)
            else
                gio = Sys.which("gio")
                gio === nothing && return "no browser opener (install xdg-utils or use gio open)"
                run(Cmd(`$gio open $url`); wait = false)
            end
        end
        return nothing
    catch e
        return "browser open failed: $(sprint(showerror, e))"
    end
end

"""
    open_local_docs(; page="index.html", dry_run=false) -> String

Open the local Documenter site in a browser. Returns a short status message
suitable for UI `last_event` or CLI println.

# Examples

```julia
open_local_docs()                    # docs/build/index.html
open_local_docs(page = "tutorial")   # tutorial.html
open_local_docs(dry_run = true)      # resolve only; no browser
```

If HTML is missing, the message tells you to build:

```bash
julia --project=docs docs/make.jl
```
"""
function open_local_docs(;
    page::AbstractString = "index.html",
    dry_run::Bool = false,
)::String
    path = resolve_local_docs_file(page)
    if path === nothing
        return "docs not built — run: julia --project=docs docs/make.jl"
    end
    url = file_url(path)
    if dry_run
        return "docs ready: $url"
    end
    err = open_in_browser(url)
    return err === nothing ? "opened docs in browser ($page)" : "docs: $err"
end

"""Common pages for the workbench help menu."""
const LOCAL_DOCS_PAGES = (
    "index.html",
    "tutorial.html",
    "spc-workbench.html",
    "recording-demos.html",
    "api.html",
)
