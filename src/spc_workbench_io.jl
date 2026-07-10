# SPC Workbench I/O — CSV import/export (series-first, Phase A)
#
# Limitation (documented): simple comma split only — no full RFC4180 quoted-field
# support in P0. Quoted commas are not handled; use unquoted Value columns.
# Included after spc_workbench.jl from TachikomaTUI.jl.

using Statistics: mean, std

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
    m.paused = true
    m.last_event = "imported $(length(parsed.values)) values from $path"
    if idx == clamp(m.active, 1, length(m.charts))
        _ensure_charts!(m)
    end
    return parsed
end

# ── CSV export (PR4b) ───────────────────────────────────────────────────

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
