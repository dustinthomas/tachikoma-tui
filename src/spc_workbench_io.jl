# SPC Workbench I/O — CSV import (PR3) + JSON session persistence schema v1 (PR4)
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

    visual_prefs = _bool_dict_from_json(get(d, "visual_prefs", nothing), DEFAULT_VISUAL_PREFS)
    visual_prefs isa String && return visual_prefs

    paused = _json_bool(get(d, "paused", nothing), false)

    return (
        charts = charts,
        active = active,
        tools = tools,
        default_rules = default_rules,
        show_chart_lines = show_lines,
        visual_prefs = visual_prefs,
        paused = paused,
    )
end

function _clear_load_ephemerals!(m::SPCWorkbenchModel)
    m.config_open = false
    m.config_selected = 1
    m.editing = nothing
    m.edit_buf = ""
    m.hovered = nothing
    m.selected = nothing
    m.hover_x = nothing
    m.drag_start = nothing
    m.view_mode = :dashboard
    # Optional fields added by later PRs (prompt state machine)
    if hasfield(typeof(m), :prompt_kind)
        setfield!(m, :prompt_kind, nothing)
    end
    if hasfield(typeof(m), :prompt_buf)
        setfield!(m, :prompt_buf, "")
    end
    if hasfield(typeof(m), :pending_delete)
        setfield!(m, :pending_delete, false)
    end
    return nothing
end

function _apply_parsed!(m::SPCWorkbenchModel, parsed::NamedTuple)
    # Preserve: rng, tick, quit, plot_area/side_area geometry, live_max
    m.charts = parsed.charts
    m.active = parsed.active
    m.tools = parsed.tools
    m.enabled_rules = parsed.default_rules
    m.show_chart_lines = parsed.show_chart_lines
    m.visual_prefs = parsed.visual_prefs
    m.paused = parsed.paused
    m.library_selected = clamp(parsed.active, 1, length(parsed.charts))
    _clear_load_ephemerals!(m)
    _ensure_charts!(m)  # sync legacy mirrors from new active
    return nothing
end

# ── Public API ──────────────────────────────────────────────────────────

"""
    workbench_to_dict(m::SPCWorkbenchModel) -> Dict

Serialize workbench session to JSON-ready Dict (schema v1).
Always writes per-chart `live_enabled`. Never writes admins/passcodes.

**PR6 known limit (schema v1):** `m.table::SharedTable` is **not** persisted.
Charts keep copy-on-map series in `values` + `source`/`col_*` maps, so display
works after load; builder re-materialize needs an empty table until CSV re-import
(or a future schema bump that stores `table: {columns, rows}`). KD25: table is
in-memory after import only.
"""
function workbench_to_dict(m::SPCWorkbenchModel)::Dict
    _ensure_charts!(m)
    _sync_active_back!(m)
    charts = [_chart_to_dict(ch) for ch in m.charts]
    tools = [Dict{String,Any}("id" => t.id, "description" => t.description) for t in m.tools]
    return Dict{String,Any}(
        "version" => _WB_SCHEMA_VERSION,
        "active" => clamp(m.active, 1, max(1, length(m.charts))),
        "charts" => charts,
        "tools" => tools,
        "default_rules" => Dict{String,Any}(k => v for (k, v) in m.enabled_rules),
        "show_chart_lines" => Dict{String,Any}(k => v for (k, v) in m.show_chart_lines),
        "visual_prefs" => Dict{String,Any}(k => v for (k, v) in m.visual_prefs),
        "paused" => m.paused,
    )
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
Replaces charts/active/tools/optional prefs; clears UI ephemerals;
preserves rng/tick/quit/geometry/live_max.
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
    # On load err: clear prompt_kind when present; keep prompt_buf for path edit
    if hasfield(typeof(m), :prompt_kind)
        setfield!(m, :prompt_kind, nothing)
    end
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
        if hasfield(typeof(m), :last_workbench_path)
            m.last_workbench_path = String(path)
        end
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
    if hasfield(typeof(m), :last_workbench_path)
        m.last_workbench_path = String(path)
    end
    m.last_event = "loaded $(basename(String(path)))"
    return m
end

"""
    load_workbench!(m, path) -> nothing | String

In-session reload into existing model (library W). Fail closed on chart mutate.
Sets `m.last_event` to `"loaded …"` or `"load err: …"`; clears `prompt_kind`
on err (keeps `prompt_buf` when present).
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
    if hasfield(typeof(m), :last_workbench_path)
        m.last_workbench_path = String(path)
    end
    m.last_event = "loaded $(basename(String(path)))"
    return nothing
end

export workbench_to_dict, workbench_from_dict, workbench_from_dict!
export save_workbench, load_workbench, load_workbench!
