# SPC Workbench I/O — CSV import (PR3) + JSON session persistence schema v1 (PR4)
# + HTML #spc-state / exportArchive import (PR10 P2; strip admins; no Excel).
# Included after spc_workbench.jl from TachikomaTUI.jl.
# CSV: simple comma split only (no full RFC4180). JSON: fail closed; no admins.

using Statistics: mean, std
using JSON

# ── Parse result types ──────────────────────────────────────────────────

struct CsvParseOk
    columns::Vector{String}
    rows::Vector{Vector{String}}
    values::Vector{Float64}
    value_col::String
    warnings::Vector{String}
end

struct CsvParseErr
    kind::Symbol  # :not_found | :unreadable | :empty | :no_header_match |
                  # :no_numeric | :all_invalid | :too_large | :bad_index
    message::String
end

"""Map parse/import error kinds to stable UI `last_event` suffixes."""
function _import_err_suffix(err::CsvParseErr)::String
    if err.kind === :not_found
        return "not found"
    elseif err.kind === :unreadable
        return "unreadable"
    elseif err.kind === :empty
        return "empty file"
    elseif err.kind === :no_header_match
        return "no Value column"
    elseif err.kind === :no_numeric
        return "no data rows"
    elseif err.kind === :all_invalid
        return "no numeric values"
    elseif err.kind === :too_large
        return "too many rows"
    elseif err.kind === :bad_index
        return "bad chart index"
    else
        return err.message
    end
end

_import_err_event(err::CsvParseErr) = "import err: $(_import_err_suffix(err))"

"""
Sync Phase B column maps on a chart after successful CSV ingress so a later
builder apply / materialize_chart_from_table! targets the same column as Phase A.
Leaves `source=:series` until explicit materialize (copy-on-map provenance).
Optionally sets col_tool / col_time when those headers exist in the table.
"""
function _sync_chart_col_maps_from_csv!(ch::ChartSpec, parsed::CsvParseOk)
    ch.col_value = String(parsed.value_col)
    cols = parsed.columns
    # Prefer exact Tool/Timestamp headers when present (fab CSV); keep defaults otherwise
    if any(==("Tool"), cols)
        ch.col_tool = "Tool"
    elseif any(==("tool"), cols)
        ch.col_tool = "tool"
    end
    if any(==("Timestamp"), cols)
        ch.col_time = "Timestamp"
    elseif any(==("Time"), cols)
        ch.col_time = "Time"
    elseif any(==("timestamp"), cols)
        ch.col_time = "timestamp"
    end
    # source stays :series until materialize (Phase A series-owned after import)
    return nothing
end

"""
    parse_csv_table(path; value_col="Value", max_rows=50_000)

Phase A series-first CSV parser.
- Multi-column: first row is header; require `value_col` case-sensitive match (default `"Value"`).
- Single column: header optional (if first cell is non-numeric, treat as header).
- Simple comma split only (no RFC4180 quoted fields).
- Skip empty lines; non-numeric value cells → warning; ≥1 good float → Ok else `:all_invalid`.
"""
function parse_csv_table(
    path::AbstractString;
    value_col::AbstractString = "Value",
    max_rows::Int = 50_000,
)::Union{CsvParseOk,CsvParseErr}
    if !isfile(path)
        return CsvParseErr(:not_found, "not found")
    end
    text = try
        read(path, String)
    catch
        return CsvParseErr(:unreadable, "unreadable")
    end

    # Strip UTF-8 BOM
    if startswith(text, "\ufeff")
        text = text[nextind(text, firstindex(text)):end]
    end
    text = replace(replace(text, "\r\n" => "\n"), "\r" => "\n")

    lines = String[]
    for ln in split(text, '\n')
        s = strip(ln)
        isempty(s) && continue
        push!(lines, String(s))
    end
    isempty(lines) && return CsvParseErr(:empty, "empty file")

    all_rows = Vector{String}[String[String(strip(c)) for c in split(ln, ',')] for ln in lines]
    first_row = all_rows[1]
    ncols = length(first_row)
    want = String(value_col)

    columns = String[]
    data_start = 1
    value_idx = 1
    used_col = want

    if ncols == 1
        cell0 = first_row[1]
        if tryparse(Float64, cell0) === nothing
            columns = [cell0]
            used_col = cell0
            value_idx = 1
            data_start = 2
        else
            columns = [want]
            used_col = want
            value_idx = 1
            data_start = 1
        end
    else
        columns = first_row
        data_start = 2
        value_idx = findfirst(==(want), columns)
        if value_idx === nothing
            return CsvParseErr(:no_header_match, "no Value column")
        end
        used_col = want
    end

    data_rows = all_rows[data_start:end]
    if length(data_rows) > max_rows
        return CsvParseErr(:too_large, "too many rows")
    end
    if isempty(data_rows)
        return CsvParseErr(:no_numeric, "no data rows")
    end

    values = Float64[]
    warnings = String[]
    rows_out = Vector{String}[]
    for (i, row) in enumerate(data_rows)
        push!(rows_out, row)
        line_no = data_start + i - 1
        if value_idx > length(row)
            push!(warnings, "row $line_no: missing value cell")
            continue
        end
        cell = row[value_idx]
        if isempty(cell)
            push!(warnings, "row $line_no: empty value")
            continue
        end
        v = tryparse(Float64, cell)
        if v === nothing
            push!(warnings, "row $line_no: non-numeric '$cell'")
            continue
        end
        push!(values, Float64(v))
    end

    if isempty(values)
        return CsvParseErr(:all_invalid, "no numeric values")
    end

    return CsvParseOk(columns, rows_out, values, used_col, warnings)
end

"""
    import_csv_into_chart!(ch, path; value_col="Value", replace=true, max_rows=50_000, show_lines=...)

Parse CSV and on success mutate chart only:
1. replace (default) or append values
2. full-range viewport + auto_fit_viewport_y! when n>0
3. ch.live_enabled = false

Returns `CsvParseOk` or `CsvParseErr`. Does not touch model paused/last_event.
"""
function import_csv_into_chart!(
    ch::ChartSpec,
    path::AbstractString;
    value_col::AbstractString = "Value",
    replace::Bool = true,
    max_rows::Int = 50_000,
    show_lines = DEFAULT_CHART_LINES,
)::Union{CsvParseOk,CsvParseErr}
    parsed = parse_csv_table(path; value_col = value_col, max_rows = max_rows)
    parsed isa CsvParseErr && return parsed

    if replace
        empty!(ch.data.values)
    end
    append!(ch.data.values, parsed.values)

    vs = ch.data.values
    if !isempty(vs)
        ch.data.cl = mean(vs)
        ch.data.sigma = length(vs) > 1 ? std(vs; corrected = true) : 0.0
        n = length(vs)
        ch.viewport.x0 = 1
        ch.viewport.x1 = n
        lz = compute_limits_and_zones(vs; sigma_method = :mr)
        auto_fit_viewport_y!(
            ch.viewport, vs, lz;
            usl = ch.usl, lsl = ch.lsl, show_lines = show_lines,
        )
    else
        ch.viewport.x0 = 0
        ch.viewport.x1 = 0
        ch.viewport.ylo = 0.0
        ch.viewport.yhi = 1.0
        ch.data.cl = 0.0
        ch.data.sigma = 0.0
    end

    ch.live_enabled = false
    return parsed
end

function _default_import_chart_name(path::AbstractString)::String
    b = basename(String(path))
    if endswith(lowercase(b), ".csv")
        b = b[1:end-4]
    end
    return isempty(b) ? "Imported" : b
end

"""
    import_csv_new_chart!(m, path; name=..., value_col="Value", max_rows=50_000)

Add a new chart from CSV. On success: live_enabled=false on that chart only,
sets active to the new chart (so runner `load=` surfaces the series), m.paused=true,
last_event="imported N values from path". On err: no chart mutation; sets last_event
to import err prefix.
"""
function import_csv_new_chart!(
    m::SPCWorkbenchModel,
    path::AbstractString;
    name::Union{Nothing,AbstractString} = nothing,
    value_col::AbstractString = "Value",
    max_rows::Int = 50_000,
)::Union{CsvParseOk,CsvParseErr}
    parsed = parse_csv_table(path; value_col = value_col, max_rows = max_rows)
    if parsed isa CsvParseErr
        m.last_event = _import_err_event(parsed)
        return parsed
    end

    nm = name === nothing ? _default_import_chart_name(path) : String(name)
    vs = copy(parsed.values)
    cl = mean(vs)
    sig = length(vs) > 1 ? std(vs; corrected = true) : 0.0
    d = WorkbenchData(values = vs, cl = cl, sigma = sig)
    n_before = length(m.charts)
    idx = add_chart!(m; name = nm, data = d)
    ch = m.charts[idx]
    ch.live_enabled = false
    n = length(ch.data.values)
    if n > 0
        ch.viewport.x0 = 1
        ch.viewport.x1 = n
        lz = compute_limits_and_zones(ch.data.values; sigma_method = :mr)
        auto_fit_viewport_y!(
            ch.viewport, ch.data.values, lz;
            usl = ch.usl, lsl = ch.lsl, show_lines = m.show_chart_lines,
        )
    end
    # PR6 / KD25: CSV ingress fills in-memory SharedTable once (no re-read on materialize)
    fill_shared_table!(m, parsed.columns, parsed.rows)
    # Align Phase B col maps so materialize/builder apply hit the same column as Phase A
    _sync_chart_col_maps_from_csv!(ch, parsed)
    # Safety: never leave charts shorter than before on success path
    @assert length(m.charts) == n_before + 1
    # Focus imported series (runner load= / CLI ingress surfaces CSV, not Primary demo)
    set_active_chart!(m, idx)
    m.paused = true
    m.last_event = "imported $(length(parsed.values)) values from $path"
    return parsed
end

"""
    import_csv_into_model!(m, path; chart_idx=active, kwargs...)

Import CSV into an existing chart on the model (default: active). On success:
chart live_enabled=false, m.paused=true, last_event set; syncs legacy mirrors when
the target is active. On err: charts unchanged; last_event = import err.
"""
function import_csv_into_model!(
    m::SPCWorkbenchModel,
    path::AbstractString;
    chart_idx::Union{Nothing,Int} = nothing,
    value_col::AbstractString = "Value",
    replace::Bool = true,
    max_rows::Int = 50_000,
)::Union{CsvParseOk,CsvParseErr}
    _ensure_charts!(m)
    idx = chart_idx === nothing ? clamp(m.active, 1, length(m.charts)) : chart_idx
    if idx < 1 || idx > length(m.charts)
        err = CsvParseErr(:bad_index, "bad chart index")
        m.last_event = _import_err_event(err)
        return err
    end
    ch = m.charts[idx]
    snapshot_lens = [length(c.data.values) for c in m.charts]
    parsed = import_csv_into_chart!(
        ch, path;
        value_col = value_col, replace = replace, max_rows = max_rows,
        show_lines = m.show_chart_lines,
    )
    if parsed isa CsvParseErr
        # import_csv_into_chart! does not mutate on err — reaffirm
        @assert all(length(m.charts[i].data.values) == snapshot_lens[i] for i in eachindex(m.charts))
        m.last_event = _import_err_event(parsed)
        return parsed
    end
    # PR6 / KD25: refresh in-memory SharedTable from this CSV ingress
    fill_shared_table!(m, parsed.columns, parsed.rows)
    _sync_chart_col_maps_from_csv!(ch, parsed)
    m.paused = true
    m.last_event = "imported $(length(parsed.values)) values from $path"
    if idx == clamp(m.active, 1, length(m.charts))
        _ensure_charts!(m)
    end
    return parsed
end


# ── JSON schema v1 (PR4) ─────────────────────────────────────────────

# ── Helpers ─────────────────────────────────────────────────────────────

const _WB_SCHEMA_VERSION = 1
# SharedTable JSON size cap (mirror CSV max_rows default; fail closed)
const TABLE_JSON_MAX_ROWS = 50_000

function _json_null_or_float(v)::Union{Float64,Nothing,String}
    v === nothing && return nothing
    v isa Real && return Float64(v)
    if v isa AbstractString
        isempty(strip(v)) && return nothing
        try
            return parse(Float64, v)
        catch
            return "expected number or null"
        end
    end
    return "expected number or null"
end

function _json_bool(v, default::Bool)::Bool
    v === nothing && return default
    v === true && return true
    v === false && return false
    v isa Integer && return v != 0
    return default
end

function _parse_values_array(arr)::Union{Vector{Float64},String}
    arr isa AbstractVector || return "values must be an array"
    out = Vector{Float64}(undef, length(arr))
    for (i, v) in enumerate(arr)
        if v isa Real
            out[i] = Float64(v)
        elseif v isa AbstractString
            try
                out[i] = parse(Float64, v)
            catch
                return "values[$i] not numeric"
            end
        else
            return "values[$i] not numeric"
        end
    end
    return out
end

function _data_from_values(values::Vector{Float64})::WorkbenchData
    if isempty(values)
        return empty_workbench_data()
    end
    lz = compute_limits_and_zones(values; sigma_method = :mr)
    return WorkbenchData(values = values, cl = lz.cl, sigma = lz.sigma)
end

function _rules_from_json(v)::Union{Dict{String,Bool},String}
    v === nothing && return copy(DEFAULT_WECO_RULES)
    v isa AbstractDict || return "enabled_rules must be an object"
    rules = copy(DEFAULT_WECO_RULES)
    for (k, rv) in v
        rules[String(k)] = _json_bool(rv, get(DEFAULT_WECO_RULES, String(k), false))
    end
    return rules
end

function _bool_dict_from_json(v, defaults::Dict{String,Bool})::Union{Dict{String,Bool},String}
    v === nothing && return copy(defaults)
    v isa AbstractDict || return "expected object for bool-dict field"
    out = copy(defaults)
    for (k, rv) in v
        out[String(k)] = _json_bool(rv, get(defaults, String(k), false))
    end
    return out
end

"""Parse optional chart_line_styles object. Fail-closed on unknown styles / wrong types.
Missing key → defaults. Unknown keys ignored. Partial known keys merge onto defaults."""
function _style_dict_from_json(v, defaults::Dict{String,String})::Union{Dict{String,String},String}
    v === nothing && return copy(defaults)
    v isa AbstractDict || return "chart_line_styles must be an object"
    out = copy(defaults)
    allowed = Set(LINE_STYLE_KEYS)
    for (k, rv) in v
        ks = String(k)
        haskey(out, ks) || continue          # ignore unknown keys
        rv isa AbstractString || return "chart_line_styles.$ks must be a string"
        s = String(rv)
        s in allowed || return "chart_line_styles.$ks unknown style: $s"  # fail-closed
        out[ks] = s
    end
    return out
end

"""
    graph_preset_to_dict(p; include_path=false) -> Dict

Serialize one GraphPreset (no series data). Used for session `graph_presets`
array and standalone preset files.

`include_path=true` embeds host-local `path` when non-empty (session list only).
Standalone file save always uses `include_path=false` so portable JSON never
embeds absolute paths (KD-SE-4).
"""
function graph_preset_to_dict(p::GraphPreset; include_path::Bool = false)::Dict{String,Any}
    d = Dict{String,Any}(
        "name" => p.name,
        "show_chart_lines" => Dict{String,Any}(k => v for (k, v) in p.show_chart_lines),
        "chart_line_styles" => Dict{String,Any}(k => v for (k, v) in p.chart_line_styles),
        "visual_prefs" => Dict{String,Any}(k => v for (k, v) in p.visual_prefs),
        "enabled_rules" => Dict{String,Any}(k => v for (k, v) in p.enabled_rules),
    )
    if include_path && !isempty(strip(p.path))
        d["path"] = p.path
    end
    return d
end

"""
    graph_preset_from_dict(d) -> GraphPreset | String

Parse one GraphPreset. Fail-closed on bad types / unknown line styles.
Missing optional fields use module defaults. Optional `path` is read when present
(session / index); standalone files typically omit it.
"""
function graph_preset_from_dict(d)::Union{GraphPreset,String}
    d isa AbstractDict || return "graph preset must be an object"
    name = get(d, "name", nothing)
    name isa AbstractString || return "graph preset name required"
    n = strip(String(name))
    isempty(n) && return "graph preset name empty"

    lines = _bool_dict_from_json(get(d, "show_chart_lines", nothing), DEFAULT_CHART_LINES)
    lines isa String && return lines
    styles = _style_dict_from_json(get(d, "chart_line_styles", nothing), DEFAULT_CHART_LINE_STYLES)
    styles isa String && return styles
    vis = _bool_dict_from_json(get(d, "visual_prefs", nothing), DEFAULT_VISUAL_PREFS)
    vis isa String && return vis
    rules = _rules_from_json(get(d, "enabled_rules", nothing))
    rules isa String && return rules

    path_raw = get(d, "path", "")
    # Strip whitespace; non-string path ignored (optional host field, not fail-closed)
    path_s = path_raw isa AbstractString ? strip(String(path_raw)) : ""

    return GraphPreset(
        name = n,
        show_chart_lines = lines,
        chart_line_styles = styles,
        visual_prefs = vis,
        enabled_rules = rules,
        path = path_s,
    )
end

function _graph_presets_from_json(v)::Union{Vector{GraphPreset},String}
    v === nothing && return GraphPreset[]
    v isa AbstractVector || return "graph_presets must be an array"
    out = GraphPreset[]
    for (i, item) in enumerate(v)
        p = graph_preset_from_dict(item)
        p isa String && return "graph_presets[$i]: $p"
        push!(out, p)
    end
    return out
end

"""
    save_graph_preset(p, path) -> nothing | String

Write a standalone graph-preset JSON file (`kind=graph_preset`, `version=1`).
"""
function save_graph_preset(p::GraphPreset, path::AbstractString)::Union{Nothing,String}
    try
        # Standalone file body never embeds host paths (KD-SE-4)
        d = graph_preset_to_dict(p; include_path = false)
        d["kind"] = "graph_preset"
        d["version"] = 1
        open(path, "w") do io
            JSON.print(io, d)
        end
        return nothing
    catch e
        return "save err: $(sprint(showerror, e))"
    end
end

"""
    load_graph_preset(path) -> GraphPreset | String

Load a standalone graph-preset JSON file. Accepts `kind=graph_preset` or
`kind=graph_config` (load-only alias; PR4), or a bare object with the preset
fields. Fail-closed on unreadable / invalid. Write path still uses `graph_preset`.
"""
function load_graph_preset(path::AbstractString)::Union{GraphPreset,String}
    local d
    try
        text = read(path, String)
        d = JSON.parse(text)
    catch e
        return "load err: unreadable ($(sprint(showerror, e)))"
    end
    d isa AbstractDict || return "load err: graph preset must be an object"
    kind = get(d, "kind", nothing)
    if kind !== nothing
        ks = String(kind)
        if ks != "graph_preset" && ks != "graph_config"
            return "load err: not a graph_preset (kind=$(kind))"
        end
    end
    p = graph_preset_from_dict(d)
    p isa String && return "load err: $p"
    return p
end

# ── File browser listing + graph-config index (PR2 pure IO) ─────────────

# FileBrowserEntry is defined in spc_workbench.jl (model field type).

"""
    list_browser_entries(cwd; show_hidden=false, file_pred, max_entries=500)
        -> Vector{FileBrowserEntry} | String

Pure directory listing for the file explorer (KD-SE-15).

- Resolves `cwd` with `abspath(expanduser(...))`.
- Includes parent `..` when not filesystem root.
- Directories first (alpha), then files matching `file_pred` (default `*.json`
  case-insensitive).
- Hidden names (leading `.`) omitted unless `show_hidden`.
- Caps at `max_entries` (parent `..` counts toward the cap when present).
- Errors → string (`"browser err: …"`); never throws into `update!`.
"""
function list_browser_entries(
    cwd::AbstractString;
    show_hidden::Bool = false,
    file_pred = (name -> endswith(lowercase(name), ".json")),
    max_entries::Int = 500,
)::Union{Vector{FileBrowserEntry},String}
    try
        root = abspath(expanduser(String(cwd)))
        isdir(root) || return "browser err: not a directory: $root"
        max_entries < 1 && return FileBrowserEntry[]

        entries = FileBrowserEntry[]
        parent = dirname(root)
        if parent != root  # not filesystem root
            push!(entries, FileBrowserEntry(; name = "..", path = parent, is_dir = true, is_parent = true))
        end

        names = readdir(root)
        dirs = String[]
        files = String[]
        for name in names
            if !show_hidden && startswith(name, ".")
                continue
            end
            full = joinpath(root, name)
            if isdir(full)
                push!(dirs, name)
            elseif isfile(full) && file_pred(name)
                push!(files, name)
            end
        end
        sort!(dirs)
        sort!(files)
        for name in dirs
            length(entries) >= max_entries && break
            push!(
                entries,
                FileBrowserEntry(; name = name, path = joinpath(root, name), is_dir = true, is_parent = false),
            )
        end
        for name in files
            length(entries) >= max_entries && break
            push!(
                entries,
                FileBrowserEntry(; name = name, path = joinpath(root, name), is_dir = false, is_parent = false),
            )
        end
        return entries
    catch e
        return "browser err: $(sprint(showerror, e))"
    end
end

# ── Graph config index (XDG data dir; KD-SE-5) ──────────────────────────

const GRAPH_CONFIG_INDEX_CAP = 50
const GRAPH_CONFIG_INDEX_VERSION = 1
const GRAPH_CONFIG_INDEX_KIND = "graph_config_index"

"""One known graph-config file reference (no full preset body)."""
@kwdef mutable struct GraphConfigIndexEntry
    name::String = ""
    path::String = ""
    saved_at::String = ""
    last_used_at::String = ""
    summary::Dict{String,Any} = Dict{String,Any}()
end

"""XDG data base + `tachikoma-tui` subdir (KD-SE-5)."""
function _tachikoma_data_dir()::String
    xdg = get(ENV, "XDG_DATA_HOME", "")
    base = !isempty(strip(xdg)) ? expanduser(strip(xdg)) :
           joinpath(homedir(), ".local", "share")
    return joinpath(base, "tachikoma-tui")
end

"""Default absolute path for the durable graph-config index file."""
function default_graph_config_index_path()::String
    return joinpath(_tachikoma_data_dir(), "graph_config_index.json")
end

"""ISO-ish local timestamp without a Dates dependency (stdlib pin)."""
function _index_timestamp()::String
    # Libc.strftime is available via Base; format is stable for MRU string sort
    return Libc.strftime("%Y-%m-%dT%H:%M:%S", time())
end

"""Summary chips for index rows (weco_on / lines_off / styles)."""
function graph_preset_index_summary(p::GraphPreset)::Dict{String,Any}
    styles = unique(collect(values(p.chart_line_styles)))
    style_s = length(styles) == 1 ? String(first(styles)) : "mixed"
    return Dict{String,Any}(
        "weco_on" => count(values(p.enabled_rules)),
        "lines_off" => count(!, values(p.show_chart_lines)),
        "styles" => style_s,
    )
end

function _index_entry_to_dict(e::GraphConfigIndexEntry)::Dict{String,Any}
    return Dict{String,Any}(
        "name" => e.name,
        "path" => e.path,
        "saved_at" => e.saved_at,
        "last_used_at" => e.last_used_at,
        "summary" => Dict{String,Any}(k => v for (k, v) in e.summary),
    )
end

function _index_entry_from_dict(d)::Union{GraphConfigIndexEntry,Nothing}
    d isa AbstractDict || return nothing
    path = get(d, "path", nothing)
    path isa AbstractString || return nothing
    ps = strip(String(path))
    isempty(ps) && return nothing
    name_raw = get(d, "name", "")
    name_s = name_raw isa AbstractString ? String(name_raw) : ""
    saved = get(d, "saved_at", "")
    saved_s = saved isa AbstractString ? String(saved) : ""
    used = get(d, "last_used_at", "")
    used_s = used isa AbstractString ? String(used) : ""
    sum_raw = get(d, "summary", nothing)
    summary = Dict{String,Any}()
    if sum_raw isa AbstractDict
        for (k, v) in sum_raw
            summary[String(k)] = v
        end
    end
    return GraphConfigIndexEntry(;
        name = name_s,
        path = ps,
        saved_at = saved_s,
        last_used_at = used_s,
        summary = summary,
    )
end

"""
    read_graph_config_index(path) -> Vector{GraphConfigIndexEntry}

Load index entries. Missing file, corrupt JSON, or unknown version → empty
vector (fail-closed; never throws). Path is normalized with
`abspath(expanduser(...))` so `~/…` resolves like write.
"""
function read_graph_config_index(path::AbstractString)::Vector{GraphConfigIndexEntry}
    try
        raw = strip(String(path))
        isempty(raw) && return GraphConfigIndexEntry[]
        p = abspath(expanduser(raw))
        isfile(p) || return GraphConfigIndexEntry[]
        text = read(p, String)
        d = JSON.parse(text)
        d isa AbstractDict || return GraphConfigIndexEntry[]
        ver = get(d, "version", nothing)
        ver_ok = ver isa Integer ? Int(ver) == GRAPH_CONFIG_INDEX_VERSION :
                 ver isa AbstractFloat ? Int(ver) == GRAPH_CONFIG_INDEX_VERSION :
                 ver isa AbstractString ? tryparse(Int, String(ver)) == GRAPH_CONFIG_INDEX_VERSION :
                 false
        ver_ok || return GraphConfigIndexEntry[]
        kind = get(d, "kind", nothing)
        if kind !== nothing && String(kind) != GRAPH_CONFIG_INDEX_KIND
            return GraphConfigIndexEntry[]
        end
        ents = get(d, "entries", nothing)
        ents isa AbstractVector || return GraphConfigIndexEntry[]
        out = GraphConfigIndexEntry[]
        for item in ents
            e = _index_entry_from_dict(item)
            e === nothing && continue
            push!(out, e)
        end
        return out
    catch
        return GraphConfigIndexEntry[]
    end
end

"""
    write_graph_config_index(path, entries) -> nothing | String

Write index JSON. Creates parent dirs via `mkpath`. Prefers atomic temp+rename
in the same directory. Path is normalized with `abspath(expanduser(...))`.
Fail-closed error string on failure (`"index err: …"`); never throws into UI.
"""
function write_graph_config_index(
    path::AbstractString,
    entries::AbstractVector{<:GraphConfigIndexEntry},
)::Union{Nothing,String}
    tmp = ""
    try
        raw = strip(String(path))
        isempty(raw) && return "index err: empty path"
        p = abspath(expanduser(raw))
        dir = dirname(p)
        try
            mkpath(dir)
        catch e
            return "index err: mkpath failed ($(sprint(showerror, e)))"
        end
        d = Dict{String,Any}(
            "version" => GRAPH_CONFIG_INDEX_VERSION,
            "kind" => GRAPH_CONFIG_INDEX_KIND,
            "entries" => [_index_entry_to_dict(e) for e in entries],
        )
        # Same-dir temp for atomic rename; pid+rand avoids collision
        tmp = joinpath(dir, ".graph_config_index.tmp.$(getpid()).$(string(rand(UInt32); base = 16))")
        open(tmp, "w") do io
            JSON.print(io, d)
        end
        mv(tmp, p; force = true)
        tmp = ""
        return nothing
    catch e
        try
            !isempty(tmp) && isfile(tmp) && rm(tmp; force = true)
        catch
        end
        return "index err: $(sprint(showerror, e))"
    end
end

"""
    upsert_graph_config_index_entry!(entries, entry; cap=50) -> nothing

Path-keyed upsert (absolute path identity via `abspath(expanduser(...))`).
Updates name/summary/timestamps from `entry`. Empty `last_used_at` (and
`saved_at` when empty) is filled with `_index_timestamp()` so a new push at
cap is never immediately evicted. Cap drops oldest `last_used_at`. Empty path → no-op.
"""
function upsert_graph_config_index_entry!(
    entries::Vector{GraphConfigIndexEntry},
    entry::GraphConfigIndexEntry;
    cap::Int = GRAPH_CONFIG_INDEX_CAP,
)::Nothing
    raw = strip(entry.path)
    isempty(raw) && return nothing
    path = abspath(expanduser(raw))
    entry.path = path
    if isempty(strip(entry.last_used_at))
        entry.last_used_at = _index_timestamp()
    end
    if isempty(strip(entry.saved_at))
        entry.saved_at = entry.last_used_at
    end
    i = findfirst(e -> abspath(expanduser(strip(e.path))) == path, entries)
    if i !== nothing
        entries[i] = entry
    else
        push!(entries, entry)
    end
    if cap > 0 && length(entries) > cap
        # Drop oldest last_used_at until within cap (stable for ties: first min wins)
        while length(entries) > cap
            _, oldest = findmin(e -> e.last_used_at, entries)
            deleteat!(entries, oldest)
        end
    end
    return nothing
end

"""Build an index entry from a GraphPreset (requires non-empty path)."""
function graph_config_index_entry_from_preset(
    p::GraphPreset;
    now::AbstractString = _index_timestamp(),
)::Union{GraphConfigIndexEntry,Nothing}
    raw = strip(p.path)
    isempty(raw) && return nothing
    ts = String(now)
    return GraphConfigIndexEntry(;
        name = p.name,
        path = abspath(expanduser(raw)),
        saved_at = ts,
        last_used_at = ts,
        summary = graph_preset_index_summary(p),
    )
end

"""
    remove_graph_config_index_entry!(entries, path) -> Bool

Path-keyed remove (absolute path identity). Returns true if an entry was
removed. Empty path → false. Never touches the filesystem file (KD-SE-9).
"""
function remove_graph_config_index_entry!(
    entries::Vector{GraphConfigIndexEntry},
    path::AbstractString,
)::Bool
    raw = strip(String(path))
    isempty(raw) && return false
    ap = abspath(expanduser(raw))
    i = findfirst(e -> abspath(expanduser(strip(e.path))) == ap, entries)
    i === nothing && return false
    deleteat!(entries, i)
    return true
end

function _tools_registry_from_json(v)::Union{Vector{ToolEntry},String}
    v === nothing && return ToolEntry[]
    v isa AbstractVector || return "tools must be an array"
    out = ToolEntry[]
    for (i, item) in enumerate(v)
        item isa AbstractDict || return "tools[$i] must be an object"
        id = get(item, "id", nothing)
        id isa AbstractString || return "tools[$i].id required string"
        desc = get(item, "description", "")
        desc = desc === nothing ? "" : String(desc)
        push!(out, ToolEntry(id = String(id), description = desc))
    end
    return out
end

function _viewport_from_json(v, data::WorkbenchData; usl=nothing, lsl=nothing, show_lines=DEFAULT_CHART_LINES)::Union{Viewport,String}
    if v === nothing
        return _boot_viewport(data; usl = usl, lsl = lsl, show_lines = show_lines)
    end
    v isa AbstractDict || return "viewport must be an object"
    try
        nn = length(data.values)
        x0 = Int(get(v, "x0", nn > 0 ? 1 : 0))
        x1 = Int(get(v, "x1", nn > 0 ? nn : 0))
        ylo = Float64(get(v, "ylo", 0.0))
        yhi = Float64(get(v, "yhi", 1.0))
        return Viewport(x0 = x0, x1 = x1, ylo = ylo, yhi = yhi)
    catch
        return "viewport fields invalid"
    end
end

function _chart_to_dict(ch::ChartSpec)::Dict{String,Any}
    d = Dict{String,Any}(
        "id" => ch.id,
        "name" => ch.name,
        "chart_type" => chart_type_to_string(ch.chart_type),
        "values" => collect(Float64, ch.data.values),
        "usl" => ch.usl,
        "target" => ch.target,
        "lsl" => ch.lsl,
        "enabled_rules" => Dict{String,Any}(k => v for (k, v) in ch.enabled_rules),
        "param" => ch.param,
        "units" => ch.units,
        "owner" => ch.owner,
        "tools" => collect(String, ch.tools),
        "limits_mode" => String(ch.limits_mode),
        "manual_cl" => ch.manual_cl,
        "manual_ucl" => ch.manual_ucl,
        "manual_lcl" => ch.manual_lcl,
        "subgroup_size" => ch.subgroup_size,
        "live_enabled" => ch.live_enabled,  # always write
        "source" => String(ch.source),
        "col_value" => ch.col_value,
        "col_n" => ch.col_n,
        "col_tool" => ch.col_tool,
        "col_time" => ch.col_time,
        "col_lot" => ch.col_lot,  # always write (P2-PR3 / KD-P2-18)
        "viewport" => Dict{String,Any}(
            "x0" => ch.viewport.x0,
            "x1" => ch.viewport.x1,
            "ylo" => ch.viewport.ylo,
            "yhi" => ch.viewport.yhi,
        ),
    )
    return d
end

function _chart_from_dict(cd)::Union{ChartSpec,String}
    cd isa AbstractDict || return "chart must be an object"
    # Never deserialize admins/passcodes — keys ignored if present.
    for req in ("id", "name", "chart_type", "values")
        haskey(cd, req) || return "chart missing required key: $req"
    end
    id = cd["id"]
    name = cd["name"]
    (id isa AbstractString && name isa AbstractString) || return "chart id/name must be strings"
    ct = parse_chart_type(String(cd["chart_type"]))
    ct === nothing && return "unknown chart_type: $(cd["chart_type"])"
    vals = _parse_values_array(cd["values"])
    vals isa String && return vals
    data = _data_from_values(vals)

    usl = _json_null_or_float(get(cd, "usl", nothing))
    usl isa String && return "usl: $usl"
    target = _json_null_or_float(get(cd, "target", nothing))
    target isa String && return "target: $target"
    lsl = _json_null_or_float(get(cd, "lsl", nothing))
    lsl isa String && return "lsl: $lsl"

    rules = _rules_from_json(get(cd, "enabled_rules", nothing))
    rules isa String && return rules

    param = String(get(cd, "param", "") === nothing ? "" : get(cd, "param", ""))
    units = String(get(cd, "units", "") === nothing ? "" : get(cd, "units", ""))
    owner = String(get(cd, "owner", "") === nothing ? "" : get(cd, "owner", ""))

    tools_v = get(cd, "tools", nothing)
    chart_tools = String[]
    if tools_v !== nothing
        tools_v isa AbstractVector || return "chart tools must be an array"
        for (i, t) in enumerate(tools_v)
            t isa AbstractString || return "chart tools[$i] must be string"
            push!(chart_tools, String(t))
        end
    end

    lm_raw = get(cd, "limits_mode", "auto")
    lm = if lm_raw === nothing || lm_raw == "auto" || lm_raw === :auto
        :auto
    elseif lm_raw == "manual" || lm_raw === :manual
        :manual
    else
        return "limits_mode must be auto|manual"
    end

    manual_cl = _json_null_or_float(get(cd, "manual_cl", nothing))
    manual_cl isa String && return "manual_cl: $manual_cl"
    manual_ucl = _json_null_or_float(get(cd, "manual_ucl", nothing))
    manual_ucl isa String && return "manual_ucl: $manual_ucl"
    manual_lcl = _json_null_or_float(get(cd, "manual_lcl", nothing))
    manual_lcl isa String && return "manual_lcl: $manual_lcl"

    sg = get(cd, "subgroup_size", 5)
    subgroup_size = try
        Int(sg === nothing ? 5 : sg)
    catch
        return "subgroup_size must be integer"
    end

    # Safe default: omitted live_enabled → false (always written by workbench_to_dict)
    live_enabled = _json_bool(get(cd, "live_enabled", nothing), false)

    src_raw = get(cd, "source", "series")
    source = if src_raw === nothing || src_raw == "series" || src_raw === :series
        :series
    elseif src_raw == "table" || src_raw === :table
        :table
    else
        :series  # unknown → safe series provenance
    end
    col_value = String(get(cd, "col_value", "Value") === nothing ? "Value" : get(cd, "col_value", "Value"))
    col_n = String(get(cd, "col_n", "") === nothing ? "" : get(cd, "col_n", ""))
    col_tool = String(get(cd, "col_tool", "Tool") === nothing ? "Tool" : get(cd, "col_tool", "Tool"))
    col_time = String(get(cd, "col_time", "Timestamp") === nothing ? "Timestamp" : get(cd, "col_time", "Timestamp"))
    # Optional col_lot (P2-PR3); omitted / null → ""
    col_lot = String(get(cd, "col_lot", "") === nothing ? "" : get(cd, "col_lot", ""))

    vp = _viewport_from_json(get(cd, "viewport", nothing), data; usl = usl, lsl = lsl)
    vp isa String && return vp

    return ChartSpec(
        id = String(id),
        name = String(name),
        chart_type = ct,
        data = data,
        viewport = vp,
        usl = usl,
        target = target,
        lsl = lsl,
        enabled_rules = rules,
        param = param isa AbstractString ? String(param) : "",
        units = units isa AbstractString ? String(units) : "",
        owner = owner isa AbstractString ? String(owner) : "",
        tools = chart_tools,
        limits_mode = lm,
        manual_cl = manual_cl,
        manual_ucl = manual_ucl,
        manual_lcl = manual_lcl,
        subgroup_size = subgroup_size,
        live_enabled = live_enabled,
        source = source,
        col_value = col_value isa AbstractString ? String(col_value) : "Value",
        col_n = col_n isa AbstractString ? String(col_n) : "",
        col_tool = col_tool isa AbstractString ? String(col_tool) : "Tool",
        col_time = col_time isa AbstractString ? String(col_time) : "Timestamp",
        col_lot = col_lot isa AbstractString ? String(col_lot) : "",
    )
end

# ── SharedTable JSON (P2-PR3 / KD-P2-4 / KD-P2-18) ─────────────────────

"""True when JSON cell is scalar (null / string / number / bool)."""
_is_table_cell_scalar(x) = x === nothing || x isa AbstractString || x isa Real

"""
Fail-closed cell coerce for schema-v1 table cells.
nothing → ""; AbstractString → String; Bool/Real → string form.
Caller must gate with `_is_table_cell_scalar` (array/object rejected).
"""
function _cell_to_string(x)::String
    x === nothing && return ""
    x isa AbstractString && return String(x)
    x isa Bool && return x ? "true" : "false"
    x isa Real && return string(x)
    return ""  # unreachable when scalar-gated
end

"""
    _table_from_json(v) -> SharedTable | error String

Fail-closed SharedTable deserialize for schema v1 optional `table` key.
`nothing` / null → empty table. Wrong root type, bad columns/rows, non-scalar
cells, or rows > TABLE_JSON_MAX_ROWS → error string (atomic reject).
"""
function _table_from_json(v)::Union{SharedTable,String}
    v === nothing && return SharedTable()
    v isa AbstractDict || return "table must be an object"

    cols = String[]
    columns_raw = get(v, "columns", nothing)
    if columns_raw !== nothing
        columns_raw isa AbstractVector || return "table columns must be an array"
        for (i, c) in enumerate(columns_raw)
            c isa AbstractString || return "table columns[$i] must be string"
            push!(cols, String(c))
        end
    end

    rows_raw = get(v, "rows", nothing)
    rows_raw === nothing && return SharedTable(columns = cols, rows = Dict{String,String}[])
    rows_raw isa AbstractVector || return "table rows must be an array"
    length(rows_raw) > TABLE_JSON_MAX_ROWS &&
        return "table too large: $(length(rows_raw)) rows (max $TABLE_JSON_MAX_ROWS)"

    rows = Dict{String,String}[]
    for (i, row) in enumerate(rows_raw)
        row isa AbstractDict || return "table rows[$i] must be an object"
        d = Dict{String,String}()
        for (k, cell) in row
            ks = String(k)
            _is_table_cell_scalar(cell) || return "table rows[$i].$ks: table cell not scalar"
            d[ks] = _cell_to_string(cell)
        end
        push!(rows, d)
    end
    return SharedTable(columns = cols, rows = rows)
end

"""Serialize SharedTable to JSON-ready Dict `{columns, rows}`."""
function _table_to_dict(table::SharedTable)::Dict{String,Any}
    rows_out = Dict{String,Any}[]
    for row in table.rows
        d = Dict{String,Any}()
        for (k, v) in row
            d[k] = v
        end
        push!(rows_out, d)
    end
    return Dict{String,Any}(
        "columns" => collect(String, table.columns),
        "rows" => rows_out,
    )
end

"""
Fully validate + parse session dict into charts/active/session fields.
Returns (charts, active, session_namedtuple) or error String.
Does not mutate any model.
"""
function _parse_workbench_dict(d)::Union{NamedTuple,String}
    d isa AbstractDict || return "workbench root must be an object"
    # Strip / ignore admins & passcodes if present (HTML mistaken paste)
    # (never read them)

    haskey(d, "version") || return "missing version"
    ver = d["version"]
    ver_i = try
        Int(ver)
    catch
        return "version must be integer"
    end
    ver_i == _WB_SCHEMA_VERSION || return "unsupported version: $ver_i (need $_WB_SCHEMA_VERSION)"

    haskey(d, "charts") || return "missing charts"
    charts_raw = d["charts"]
    charts_raw isa AbstractVector || return "charts must be an array"
    isempty(charts_raw) && return "no charts"

    charts = ChartSpec[]
    for (i, cd) in enumerate(charts_raw)
        ch = _chart_from_dict(cd)
        ch isa String && return "charts[$i]: $ch"
        push!(charts, ch)
    end

    # Required key (schema v1) — same class as version/charts
    haskey(d, "active") || return "missing active"
    active_raw = d["active"]
    active = try
        Int(active_raw)
    catch
        return "active must be integer"
    end
    active = clamp(active, 1, length(charts))

    tools = _tools_registry_from_json(get(d, "tools", nothing))
    tools isa String && return tools

    default_rules = _rules_from_json(get(d, "default_rules", nothing))
    default_rules isa String && return default_rules

    show_lines = _bool_dict_from_json(get(d, "show_chart_lines", nothing), DEFAULT_CHART_LINES)
    show_lines isa String && return show_lines

    chart_line_styles = _style_dict_from_json(get(d, "chart_line_styles", nothing), DEFAULT_CHART_LINE_STYLES)
    chart_line_styles isa String && return chart_line_styles

    visual_prefs = _bool_dict_from_json(get(d, "visual_prefs", nothing), DEFAULT_VISUAL_PREFS)
    visual_prefs isa String && return visual_prefs

    graph_presets = _graph_presets_from_json(get(d, "graph_presets", nothing))
    graph_presets isa String && return graph_presets

    paused = _json_bool(get(d, "paused", nothing), false)

    # Optional SharedTable (P2-PR3); missing/null → empty; bad type → whole parse fails
    table = _table_from_json(get(d, "table", nothing))
    table isa String && return table

    return (
        charts = charts,
        active = active,
        tools = tools,
        default_rules = default_rules,
        show_chart_lines = show_lines,
        chart_line_styles = chart_line_styles,
        visual_prefs = visual_prefs,
        graph_presets = graph_presets,
        paused = paused,
        table = table,
    )
end

function _clear_load_ephemerals!(m::SPCWorkbenchModel)
    m.config_selected = 1
    m.editing = nothing
    m.edit_buf = ""
    m.hovered = nothing
    m.selected = nothing
    m.hover_x = nothing
    m.drag_start = nothing
    m.view_mode = :dashboard
    m.prompt_kind = nothing
    m.prompt_buf = ""
    m.pending_delete = false
    m.pending_overwrite = false
    m.pending_overwrite_path = ""
    m.file_browser_open = false
    # Tools registry UI ephemerals (P2-PR4) — selection/scroll/staged id not in JSON
    m.tools_selected = 1
    m.tools_scroll = 0
    m.tool_pending_id = ""
    m.tools_area = Rect(0, 0, 0, 0)
    # Session-ephemeral filters (GC-PR4) — not in JSON schema; always reset on load
    m.filter_tool = ""
    m.filter_type = ""
    m.filter_owner = ""
    m.filter_prompt_field = :tool
    # Path chrome caches rebuilt on next merge (KD-SE-25)
    empty!(m.preset_path_missing)
    empty!(m.preset_index_summary)
    # WECO explain popup (KD-WB-11) — session-ephemeral; not in JSON
    _clear_weco_explain!(m)
    return nothing
end

function _apply_parsed!(m::SPCWorkbenchModel, parsed::NamedTuple)
    # Preserve: rng, tick, quit, plot_area/side_area geometry, live_max
    m.charts = parsed.charts
    m.active = parsed.active
    m.tools = parsed.tools
    # Session defaults (KD-P2-21); per-chart rules live on chart objects.
    # m.enabled_rules is synced from active chart in _ensure_charts!.
    m.default_rules = parsed.default_rules
    m.show_chart_lines = parsed.show_chart_lines
    m.chart_line_styles = parsed.chart_line_styles
    m.visual_prefs = parsed.visual_prefs
    m.graph_presets = parsed.graph_presets
    m.paused = parsed.paused
    m.table = parsed.table  # mirror HTML apply; do NOT auto-rematerialize (KD-P2-18)
    m.library_selected = clamp(parsed.active, 1, length(parsed.charts))
    _clear_load_ephemerals!(m)
    # After clear, clamp tools_selected into new registry (empty → stays 1)
    ntools = length(m.tools)
    m.tools_selected = ntools >= 1 ? clamp(m.tools_selected, 1, ntools) : 1
    _ensure_charts!(m)  # sync legacy mirrors from new active
    return nothing
end

# ── Public API ──────────────────────────────────────────────────────────

"""
    workbench_to_dict(m::SPCWorkbenchModel) -> Dict

Serialize workbench session to JSON-ready Dict (schema v1).
Always writes per-chart `live_enabled` and `col_lot`. Never writes admins/passcodes.

Optional `table` (SharedTable as `{columns, rows}`) is written only when
non-empty (`columns` or `rows` non-empty); omitted when empty to keep fixtures
small (KD-P2-18). Load restores the table without auto-rematerializing charts —
series `values` remain display source of truth on load.
"""
function workbench_to_dict(m::SPCWorkbenchModel)::Dict
    _ensure_charts!(m)
    _sync_active_back!(m)
    charts = [_chart_to_dict(ch) for ch in m.charts]
    tools = [Dict{String,Any}("id" => t.id, "description" => t.description) for t in m.tools]
    d = Dict{String,Any}(
        "version" => _WB_SCHEMA_VERSION,
        "active" => clamp(m.active, 1, max(1, length(m.charts))),
        "charts" => charts,
        "tools" => tools,
        "default_rules" => Dict{String,Any}(k => v for (k, v) in m.default_rules),
        "show_chart_lines" => Dict{String,Any}(k => v for (k, v) in m.show_chart_lines),
        "chart_line_styles" => Dict{String,Any}(k => v for (k, v) in m.chart_line_styles),
        "visual_prefs" => Dict{String,Any}(k => v for (k, v) in m.visual_prefs),
        "paused" => m.paused,
    )
    # Omit empty presets (keep fixtures small; same policy as table).
    # Session embeds optional host `path` so list identity survives restart (KD-SE-4).
    if !isempty(m.graph_presets)
        d["graph_presets"] = [graph_preset_to_dict(p; include_path = true) for p in m.graph_presets]
    end
    # Omit empty table (KD-P2-18)
    if !isempty(m.table.columns) || !isempty(m.table.rows)
        d["table"] = _table_to_dict(m.table)
    end
    return d
end

"""
    workbench_from_dict(d) -> SPCWorkbenchModel | String

Construct a fresh model from a schema-v1 dict. Error string on failure.
"""
function workbench_from_dict(d)::Union{SPCWorkbenchModel,String}
    parsed = _parse_workbench_dict(d)
    parsed isa String && return parsed
    # Minimal placeholder data; charts from file replace seed path
    m = SPCWorkbenchModel(
        data = empty_workbench_data(),
        paused = parsed.paused,
        seed_demos = :none,
        charts = ChartSpec[],
        tools = ToolEntry[],
    )
    _apply_parsed!(m, parsed)
    return m
end

"""
    workbench_from_dict!(m, d) -> nothing | String

In-place apply. Fail closed: on error, `m` is unchanged.
Replaces charts/active/tools/table/optional prefs; clears UI ephemerals;
preserves rng/tick/quit/geometry/live_max. Does not auto-rematerialize charts.
"""
function workbench_from_dict!(m::SPCWorkbenchModel, d)::Union{Nothing,String}
    parsed = _parse_workbench_dict(d)
    parsed isa String && return parsed
    _apply_parsed!(m, parsed)
    return nothing
end

# ── Load/save UX helpers (A4 last_event prefixes) ───────────────────────

function _normalize_load_err(msg::AbstractString)::String
    s = String(msg)
    startswith(s, "load err:") && return s
    return "load err: $s"
end

function _clear_prompt_kind_keep_buf!(m::SPCWorkbenchModel)
    # On load err: clear prompt_kind; keep prompt_buf for path edit
    m.prompt_kind = nothing
    return nothing
end

function _set_load_err!(m::SPCWorkbenchModel, msg::AbstractString)::String
    out = _normalize_load_err(msg)
    m.last_event = out
    _clear_prompt_kind_keep_buf!(m)
    return out
end

"""
    save_workbench(m, path) -> nothing | String

Write schema-v1 JSON to `path`. Sets `m.last_workbench_path` and
`m.last_event = "saved …"` on success; `"save err: …"` on failure.
"""
function save_workbench(m::SPCWorkbenchModel, path::AbstractString)::Union{Nothing,String}
    try
        d = workbench_to_dict(m)
        open(path, "w") do io
            JSON.print(io, d)
        end
        m.last_workbench_path = String(path)
        m.last_event = "saved $(basename(String(path)))"
        return nothing
    catch e
        msg = "save err: $(sprint(showerror, e))"
        m.last_event = msg
        return msg
    end
end

"""
    load_workbench(path) -> SPCWorkbenchModel | String

CLI/construct: new model from JSON file.
"""
function load_workbench(path::AbstractString)::Union{SPCWorkbenchModel,String}
    local d
    try
        text = read(path, String)
        d = JSON.parse(text)
    catch e
        return _normalize_load_err("unreadable ($(sprint(showerror, e)))")
    end
    m = workbench_from_dict(d)
    m isa String && return _normalize_load_err(m)
    m.last_workbench_path = String(path)
    m.last_event = "loaded $(basename(String(path)))"
    return m
end

"""
    load_workbench!(m, path) -> nothing | String

In-session reload into existing model (library W). Fail closed on chart mutate.
Sets `m.last_event` to `"loaded …"` or `"load err: …"`; clears `prompt_kind`
on err (keeps `prompt_buf`).
"""
function load_workbench!(m::SPCWorkbenchModel, path::AbstractString)::Union{Nothing,String}
    local d
    try
        text = read(path, String)
        d = JSON.parse(text)
    catch e
        return _set_load_err!(m, "unreadable ($(sprint(showerror, e)))")
    end
    err = workbench_from_dict!(m, d)
    if err !== nothing
        return _set_load_err!(m, err)
    end
    # Disk-first: merge durable config index into session list (KD-SE-25)
    try
        _merge_graph_config_index!(m)
    catch
    end
    m.last_workbench_path = String(path)
    m.last_event = "loaded $(basename(String(path)))"
    return nothing
end

# ── HTML #spc-state / exportArchive import (PR10 P2) ───────────────────
# Maps HTML archive JSON into SharedTable + ChartSpecs. Fail closed.
# NEVER deserializes admins / passcodes (security: strip on sight).
# No XLSX.jl — HTML/JSON only.

const _HTML_ADMIN_KEYS = ("admins", "passcodes", "passcode", "admin")

"""Drop any admin/passcode keys from a dict (shallow). Returns a new Dict."""
function _strip_admin_keys(d::AbstractDict)::Dict{String,Any}
    out = Dict{String,Any}()
    for (k, v) in d
        ks = String(k)
        ks in _HTML_ADMIN_KEYS && continue
        out[ks] = v
    end
    return out
end

"""
    extract_html_spc_state(text) -> Dict | String

Pull `#spc-state` JSON from an HTML archive (or accept raw JSON that is already
the exportArchive / inline state object). Error string on failure.
Never returns a dict that still carries top-level `admins`/`passcodes`.
"""
function extract_html_spc_state(text::AbstractString)::Union{Dict{String,Any},String}
    s = String(text)
    isempty(strip(s)) && return "empty input"
    # Prefer explicit #spc-state script payload
    m = match(r"""id\s*=\s*["']spc-state["'][^>]*>(.*?)</script>"""is, s)
    json_text = if m !== nothing
        String(m.captures[1])
    else
        # Raw JSON archive (exportArchive body) — must look like an object
        t = strip(s)
        startswith(t, "{") ? t : ""
    end
    isempty(strip(json_text)) && return "no #spc-state JSON found"
    local d
    try
        d = JSON.parse(json_text)
    catch e
        return "spc-state JSON parse failed ($(sprint(showerror, e)))"
    end
    d isa AbstractDict || return "spc-state root must be an object"
    # Strip secrets immediately — never pass through
    return _strip_admin_keys(d)
end

"""
    extract_html_spc_state_file(path) -> Dict | String

Read file then `extract_html_spc_state`.
"""
function extract_html_spc_state_file(path::AbstractString)::Union{Dict{String,Any},String}
    if !isfile(path)
        return "not found"
    end
    text = try
        read(path, String)
    catch e
        return "unreadable ($(sprint(showerror, e)))"
    end
    return extract_html_spc_state(text)
end

function _html_cell_to_string(v)::String
    v === nothing && return ""
    v isa AbstractString && return String(v)
    v isa Bool && return v ? "true" : "false"
    v isa Integer && return string(Int(v))
    v isa Real && return string(Float64(v))
    return string(v)
end

"""
Build SharedTable from HTML `data` (row objects) + optional `columns`.
Empty value rows kept as empty cells (materialize skips non-numeric).
"""
function _shared_table_from_html(data, columns_raw)::Union{SharedTable,String}
    data === nothing && return SharedTable()
    data isa AbstractVector || return "data must be an array"
    cols = String[]
    if columns_raw !== nothing
        columns_raw isa AbstractVector || return "columns must be an array"
        for (i, c) in enumerate(columns_raw)
            c isa AbstractString || return "columns[$i] must be string"
            push!(cols, String(c))
        end
    end
    # Discover columns from first non-empty row if omitted
    if isempty(cols)
        for row in data
            row isa AbstractDict || continue
            for k in keys(row)
                ks = String(k)
                ks in cols || push!(cols, ks)
            end
            !isempty(cols) && break
        end
    end
    rows = Dict{String,String}[]
    for (i, row) in enumerate(data)
        row isa AbstractDict || return "data[$i] must be an object"
        d = Dict{String,String}()
        # union of declared cols + row keys (ignore admin keys if embedded)
        all_keys = copy(cols)
        for k in keys(row)
            ks = String(k)
            ks in _HTML_ADMIN_KEYS && continue
            ks in all_keys || push!(all_keys, ks)
        end
        for c in all_keys
            d[c] = _html_cell_to_string(get(row, c, ""))
        end
        push!(rows, d)
        # grow cols set for table.columns
        for c in all_keys
            c in cols || push!(cols, c)
        end
    end
    return SharedTable(columns = cols, rows = rows)
end

function _html_rules_from(v)::Union{Dict{String,Bool},String}
    # HTML uses "rules" / "defaultRules" with WECO-N keys
    return _rules_from_json(v)
end

function _html_tools_from(v)::Union{Vector{ToolEntry},String}
    v === nothing && return ToolEntry[]
    v isa AbstractVector || return "tools must be an array"
    out = ToolEntry[]
    for (i, item) in enumerate(v)
        item isa AbstractDict || return "tools[$i] must be an object"
        id = get(item, "id", nothing)
        id isa AbstractString || return "tools[$i].id required string"
        # HTML uses "desc"; schema v1 uses "description"
        desc = get(item, "description", nothing)
        if desc === nothing
            desc = get(item, "desc", "")
        end
        desc = desc === nothing ? "" : String(desc)
        push!(out, ToolEntry(id = String(id), description = desc))
    end
    return out
end

"""
Map one HTML chart object → ChartSpec (values still empty; materialize separately).
Ignores admins/passcodes on the chart object.
"""
function _chart_from_html_dict(cd)::Union{ChartSpec,String}
    cd isa AbstractDict || return "chart must be an object"
    # Required HTML keys
    haskey(cd, "id") || return "chart missing id"
    haskey(cd, "name") || return "chart missing name"
    type_raw = get(cd, "type", get(cd, "chart_type", nothing))
    type_raw === nothing && return "chart missing type"
    type_raw isa AbstractString || return "chart type must be string"
    ct = parse_chart_type(String(type_raw))
    ct === nothing && return "unknown chart type: $type_raw"
    id = cd["id"]
    name = cd["name"]
    (id isa AbstractString && name isa AbstractString) || return "chart id/name must be strings"

    usl = _json_null_or_float(get(cd, "usl", nothing))
    usl isa String && return "usl: $usl"
    target = _json_null_or_float(get(cd, "target", nothing))
    target isa String && return "target: $target"
    lsl = _json_null_or_float(get(cd, "lsl", nothing))
    lsl isa String && return "lsl: $lsl"

    rules = _html_rules_from(get(cd, "rules", get(cd, "enabled_rules", nothing)))
    rules isa String && return rules

    param = _html_cell_to_string(get(cd, "param", ""))
    units = _html_cell_to_string(get(cd, "units", ""))
    owner = _html_cell_to_string(get(cd, "owner", ""))

    tools_v = get(cd, "tools", nothing)
    chart_tools = String[]
    if tools_v !== nothing
        tools_v isa AbstractVector || return "chart tools must be an array"
        for (i, t) in enumerate(tools_v)
            t isa AbstractString || return "chart tools[$i] must be string"
            push!(chart_tools, String(t))
        end
    end

    lm_raw = get(cd, "limitsMode", get(cd, "limits_mode", "auto"))
    lm = if lm_raw === nothing || lm_raw == "auto" || lm_raw === :auto
        :auto
    elseif lm_raw == "manual" || lm_raw === :manual
        :manual
    else
        return "limitsMode must be auto|manual"
    end

    # HTML manual limits live as cl/ucl/lcl; schema uses manual_*
    manual_cl = _json_null_or_float(get(cd, "manual_cl", get(cd, "cl", nothing)))
    manual_cl isa String && return "cl: $manual_cl"
    manual_ucl = _json_null_or_float(get(cd, "manual_ucl", get(cd, "ucl", nothing)))
    manual_ucl isa String && return "ucl: $manual_ucl"
    manual_lcl = _json_null_or_float(get(cd, "manual_lcl", get(cd, "lcl", nothing)))
    manual_lcl isa String && return "lcl: $manual_lcl"
    # When mode is auto, drop manual values so resolver stays auto
    if lm === :auto
        manual_cl = nothing
        manual_ucl = nothing
        manual_lcl = nothing
    end

    sg = get(cd, "subgroupSize", get(cd, "subgroup_size", 5))
    subgroup_size = try
        Int(sg === nothing ? 5 : sg)
    catch
        return "subgroupSize must be integer"
    end

    col_value = _html_cell_to_string(get(cd, "col_value", "Value"))
    isempty(col_value) && (col_value = "Value")
    col_n = _html_cell_to_string(get(cd, "col_n", ""))
    col_tool = _html_cell_to_string(get(cd, "col_tool", "Tool"))
    isempty(col_tool) && (col_tool = "Tool")
    col_time = _html_cell_to_string(get(cd, "col_time", "Timestamp"))
    isempty(col_time) && (col_time = "Timestamp")
    col_lot = _html_cell_to_string(get(cd, "col_lot", ""))

    return ChartSpec(
        id = String(id),
        name = String(name),
        chart_type = ct,
        data = empty_workbench_data(),
        usl = usl,
        target = target,
        lsl = lsl,
        enabled_rules = rules,
        param = param,
        units = units,
        owner = owner,
        tools = chart_tools,
        limits_mode = lm,
        manual_cl = manual_cl,
        manual_ucl = manual_ucl,
        manual_lcl = manual_lcl,
        subgroup_size = subgroup_size,
        live_enabled = false,  # imported archive — never auto-live
        source = :table,
        col_value = col_value,
        col_n = col_n,
        col_tool = col_tool,
        col_time = col_time,
        col_lot = col_lot,
    )
end

"""
Fully validate + parse HTML archive dict into (charts, table, tools, default_rules).
Does not mutate any model. Never reads admins/passcodes.
"""
function _parse_html_state_dict(d)::Union{NamedTuple,String}
    d isa AbstractDict || return "html state root must be an object"
    # Explicit strip (extract already strips; defense in depth)
    d = _strip_admin_keys(d)
    # Reject schema-v1 sessions — use load_workbench / workbench_from_dict instead
    if haskey(d, "version")
        return "schema-v1 JSON — use load_workbench (not HTML archive)"
    end

    haskey(d, "charts") || return "missing charts"
    charts_raw = d["charts"]
    charts_raw isa AbstractVector || return "charts must be an array"
    isempty(charts_raw) && return "no charts"

    table = _shared_table_from_html(get(d, "data", nothing), get(d, "columns", nothing))
    table isa String && return table

    charts = ChartSpec[]
    for (i, cd) in enumerate(charts_raw)
        # Strip per-chart admin keys if present
        cd_clean = cd isa AbstractDict ? _strip_admin_keys(cd) : cd
        ch = _chart_from_html_dict(cd_clean)
        ch isa String && return "charts[$i]: $ch"
        # Materialize series from shared table (copy-on-map)
        materialize_chart_from_table!(ch, table)
        push!(charts, ch)
    end

    # At least one chart must have numeric values after materialize (fail closed)
    any_vals = any(ch -> !isempty(ch.data.values), charts)
    any_vals || return "no numeric values after mapping charts to data"

    tools = _html_tools_from(get(d, "tools", nothing))
    tools isa String && return tools

    default_rules = _html_rules_from(get(d, "defaultRules", get(d, "default_rules", nothing)))
    default_rules isa String && return default_rules

    return (
        charts = charts,
        table = table,
        tools = tools,
        default_rules = default_rules,
        active = 1,
    )
end

function _apply_html_parsed!(m::SPCWorkbenchModel, parsed::NamedTuple)
    m.charts = parsed.charts
    m.active = parsed.active
    m.tools = parsed.tools
    # Session defaults (KD-P2-21); per-chart rules stay on chart objects.
    m.default_rules = parsed.default_rules
    m.table = parsed.table
    m.library_selected = clamp(parsed.active, 1, length(parsed.charts))
    m.paused = true  # archive import pauses live (same spirit as CSV)
    _clear_load_ephemerals!(m)
    _ensure_charts!(m)
    return nothing
end

"""
    html_state_to_workbench(d) -> SPCWorkbenchModel | String

Build a fresh model from an HTML archive state dict (already extracted).
Strips admins. Fail closed → error string, no partial model.
"""
function html_state_to_workbench(d)::Union{SPCWorkbenchModel,String}
    parsed = _parse_html_state_dict(d)
    parsed isa String && return parsed
    m = SPCWorkbenchModel(
        data = empty_workbench_data(),
        paused = true,
        seed_demos = :none,
        charts = ChartSpec[],
        tools = ToolEntry[],
    )
    _apply_html_parsed!(m, parsed)
    return m
end

"""
    html_state_to_workbench!(m, d) -> nothing | String

In-place apply HTML archive. Fail closed: on error, `m` is unchanged.
Replaces charts/active/tools/table; clears UI ephemerals; preserves rng/tick/quit/geometry.
"""
function html_state_to_workbench!(m::SPCWorkbenchModel, d)::Union{Nothing,String}
    parsed = _parse_html_state_dict(d)
    parsed isa String && return parsed
    _apply_html_parsed!(m, parsed)
    return nothing
end

"""
    load_html_archive(path) -> SPCWorkbenchModel | String

CLI/construct: load HTML file (or raw JSON exportArchive) into a new model.
Strips admins/passcodes. Error string on failure.
"""
function load_html_archive(path::AbstractString)::Union{SPCWorkbenchModel,String}
    d = extract_html_spc_state_file(path)
    d isa String && return _normalize_load_err(d)
    m = html_state_to_workbench(d)
    m isa String && return _normalize_load_err(m)
    m.last_workbench_path = String(path)
    m.last_event = "loaded html $(basename(String(path)))"
    return m
end

"""
    load_html_archive!(m, path) -> nothing | String

In-session HTML archive import. Fail closed on chart mutate.
`last_event` = `"loaded html …"` or `"load err: …"`.
"""
function load_html_archive!(m::SPCWorkbenchModel, path::AbstractString)::Union{Nothing,String}
    d = extract_html_spc_state_file(path)
    if d isa String
        return _set_load_err!(m, d)
    end
    err = html_state_to_workbench!(m, d)
    if err !== nothing
        return _set_load_err!(m, err)
    end
    m.last_workbench_path = String(path)
    m.last_event = "loaded html $(basename(String(path)))"
    return nothing
end

export workbench_to_dict, workbench_from_dict, workbench_from_dict!
export save_workbench, load_workbench, load_workbench!
export graph_preset_to_dict, graph_preset_from_dict, save_graph_preset, load_graph_preset
export FileBrowserEntry, list_browser_entries
export GraphConfigIndexEntry, GRAPH_CONFIG_INDEX_CAP
export _tachikoma_data_dir, default_graph_config_index_path
export read_graph_config_index, write_graph_config_index
export upsert_graph_config_index_entry!, graph_preset_index_summary
export graph_config_index_entry_from_preset, remove_graph_config_index_entry!
export extract_html_spc_state, extract_html_spc_state_file
export html_state_to_workbench, html_state_to_workbench!
export load_html_archive, load_html_archive!

# ── CSV export (PR4b) ─────────────────────────────────────────

"""
    export_csv_series(path, values; col_name="Value") -> Union{Nothing,String}

Write a simple single-column CSV: header `col_name` then one float per line.
Returns `nothing` on success, or an error message string (fail-closed).
Symmetric with `parse_csv_table` / import (no RFC4180 quoting).
"""
function export_csv_series(
    path::AbstractString,
    values;
    col_name::AbstractString = "Value",
)::Union{Nothing,String}
    p = strip(String(path))
    isempty(p) && return "empty path"
    try
        open(p, "w") do io
            println(io, String(col_name))
            for v in values
                println(io, Float64(v))
            end
        end
    catch e
        return "unwritable: $(sprint(showerror, e))"
    end
    return nothing
end

"""
    chart_for_export(m) -> ChartSpec

When `view_mode == :library`, export the `library_selected` chart series;
otherwise fall back to the active chart (`current_chart`).
"""
function chart_for_export(m::SPCWorkbenchModel)::ChartSpec
    _ensure_charts!(m)
    if m.view_mode == :library && 1 <= m.library_selected <= length(m.charts)
        return m.charts[m.library_selected]
    end
    return current_chart(m)
end

export export_csv_series, chart_for_export

