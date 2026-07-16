# ═══════════════════════════════════════════════════════════════════════
# Local Documenter HTML — open in system browser (private / offline app)
#
# Prebuilt HTML is committed under docs/build/ so O works after git pull.
# Rebuild after editing docs/src (then commit the new build):
#   julia --project=docs docs/make.jl
# Workbench: h → O   or  open_local_docs() / scripts/open_docs.jl
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

"""Non-empty env value helper (missing keys → empty)."""
_env_get(env, key::AbstractString)::String = String(get(env, key, ""))

"""
True when a desktop/browser target is plausible.

Linux `xdg-open` often exits 0 while printing "Error: no DISPLAY" — so we must
preflight before claiming success. `BROWSER` is an explicit override (tests +
remote workflows).
"""
function _browser_target_available(env)::Bool
    !isempty(_env_get(env, "BROWSER")) && return true
    Sys.isapple() && return true
    Sys.iswindows() && return true
    return !isempty(_env_get(env, "DISPLAY")) ||
           !isempty(_env_get(env, "WAYLAND_DISPLAY"))
end

"""Build a string→string Dict from `ENV`-like for `setenv` / tests."""
function _env_dict(env)::Dict{String,String}
    d = Dict{String,String}()
    for (k, v) in env
        d[String(k)] = String(v)
    end
    return d
end

"""
Run an opener command with stdio detached from the TUI.

Uses `wait=true` when we need a reliable exit status (`BROWSER` override).
Uses detached `wait=false` for system openers after GUI preflight (they often
daemonize; blocking forever is worse than a false negative).
"""
function _run_browser_cmd(cmd::Cmd, env; wait::Bool)
    ed = _env_dict(env)
    c = setenv(cmd, ed)
    # detach so the TUI/raw terminal is not attached as the browser's controlling tty
    c = Cmd(c; detach = true, ignorestatus = true)
    if wait
        errbuf = IOBuffer()
        p = run(pipeline(c, stdin = devnull, stdout = devnull, stderr = errbuf); wait = true)
        err = strip(String(take!(errbuf)))
        if p.exitcode != 0
            return "browser open failed: " *
                   (isempty(err) ? "exit $(p.exitcode)" : err)
        end
        if occursin(r"(?i)error:|cannot open display|no display", err)
            return "browser open failed: $err"
        end
        return nothing
    else
        run(pipeline(c, stdin = devnull, stdout = devnull, stderr = devnull); wait = false)
        return nothing
    end
end

"""
    open_in_browser(path_or_url; dry_run=false, env=ENV) -> Union{Nothing,String}

Open a local path or URL in the default browser. Returns `nothing` on success
(or when `dry_run=true`), else an error message string (includes a `file://`
URL when possible so the user can open manually).

`env` is injectable for tests (e.g. clear `DISPLAY`, set `BROWSER`).
"""
function open_in_browser(
    path_or_url::AbstractString;
    dry_run::Bool = false,
    env = ENV,
)::Union{Nothing,String}
    target = String(path_or_url)
    url = if startswith(target, "http://") || startswith(target, "https://") ||
             startswith(target, "file:")
        target
    else
        isfile(target) || return "not found: $target"
        file_url(target)
    end
    dry_run && return nothing

    if !_browser_target_available(env)
        return "no DISPLAY/WAYLAND/BROWSER — open manually: $url"
    end

    try
        browser = _env_get(env, "BROWSER")
        if !isempty(browser)
            # BROWSER is a single executable path (tests + simple overrides).
            # wait=true so failures surface instead of false "opened".
            return _run_browser_cmd(Cmd(`$browser $url`), env; wait = true)
        elseif Sys.isapple()
            return _run_browser_cmd(`open $url`, env; wait = false)
        elseif Sys.iswindows()
            # empty title arg required by `start`
            return _run_browser_cmd(Cmd(`cmd /c start "" $url`), env; wait = false)
        else
            xdg = Sys.which("xdg-open")
            if xdg !== nothing
                # Prefer bare path for local files — some desktop handlers handle
                # paths more reliably than file:// URLs.
                open_target = startswith(url, "file://") && isfile(target) ? abspath(target) :
                              (startswith(url, "file://") ?
                               begin
                                   # file:///abs/path → /abs/path
                                   p = replace(url, r"^file://" => "")
                                   isfile(p) ? p : url
                               end : url)
                return _run_browser_cmd(Cmd(`$xdg $open_target`), env; wait = false)
            end
            gio = Sys.which("gio")
            gio === nothing &&
                return "no browser opener (install xdg-utils) — open manually: $url"
            return _run_browser_cmd(Cmd(`$gio open $url`), env; wait = false)
        end
    catch e
        return "browser open failed: $(sprint(showerror, e)) — open manually: $url"
    end
end

"""
    open_local_docs(; page="index.html", dry_run=false, env=ENV) -> String

Open the local Documenter site in a browser. Returns a short status message
suitable for UI `last_event` or CLI println.

# Examples

```julia
open_local_docs()                    # docs/build/index.html
open_local_docs(page = "tutorial")   # tutorial.html
open_local_docs(dry_run = true)      # resolve only; no browser
```

If HTML is missing (e.g. partial checkout), the message tells you to rebuild:

```bash
julia --project=docs docs/make.jl
```
"""
function open_local_docs(;
    page::AbstractString = "index.html",
    dry_run::Bool = false,
    env = ENV,
)::String
    path = resolve_local_docs_file(page)
    if path === nothing
        return "docs not built — run: julia --project=docs docs/make.jl (or git pull for prebuilt docs/build)"
    end
    url = file_url(path)
    if dry_run
        return "docs ready: $url"
    end
    err = open_in_browser(url; env = env)
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
