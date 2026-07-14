# ═══════════════════════════════════════════════════════════════════════
# SPC Workbench (pure) — WECO rules detector + stats helpers + generator
#
# Slice 1/7: no UI, no Tachikoma dep, full port of WECO 1-8 from HTML mockup.
# Pure functions for later caching / workbench.
# Uses 1-based indices in WECOViolation.
# Follows patterns from src/spc.jl (structs, @kwdef, Statistics, Random).
# ═══════════════════════════════════════════════════════════════════════

using Random
using Statistics: mean, std

# ── Data structs (for compatibility with later slices; pure here) ───────

struct WECOViolation
    rule::String
    index::Int   # 1-based
    msg::String
end

@kwdef mutable struct WorkbenchData
    values::Vector{Float64}
    cl::Float64
    sigma::Float64
    meta::Dict{String,Any} = Dict{String,Any}()
end

# Early Viewport (for ChartSpec default in pure include order)
if !isdefined(@__MODULE__, :Viewport)
@kwdef mutable struct Viewport
    x0::Int = 1
    x1::Int = 1
    ylo::Float64 = 0.0
    yhi::Float64 = 1.0
end
end

struct LimitsAndZones
    cl::Float64
    sigma::Float64
    ucl::Float64
    lcl::Float64
    ucl2::Float64
    lcl2::Float64
    ucl1::Float64
    lcl1::Float64
end

struct CapabilityResult
    cpk::Union{Float64,Nothing}
    cpu::Union{Float64,Nothing}
    cpl::Union{Float64,Nothing}
    cpk_sigma::Float64
end

# ── Defaults matching HTML mockup exactly ───────────────────────────────
# (Defined before ChartSpec so @kwdef defaults can reference them at construct time.)

const DEFAULT_WECO_RULES = Dict{String,Bool}(
    "WECO-1" => true,
    "WECO-2" => true,
    "WECO-3" => true,
    "WECO-4" => true,
    "WECO-5" => true,
    "WECO-6" => false,
    "WECO-7" => false,
    "WECO-8" => false,
)

# ── Chart types (wire format aligned with HTML) ─────────────────────────

@enum ChartType begin
    I_MR
    Xbar_R
    Xbar_S
    p_chart
    np_chart
    c_chart
    u_chart
end

const CHART_TYPE_WIRE = Dict(
    I_MR => "I-MR",
    Xbar_R => "Xbar-R",
    Xbar_S => "Xbar-S",
    p_chart => "p",
    np_chart => "np",
    c_chart => "c",
    u_chart => "u",
)

# Reverse wire lookup + Julia enum-name aliases (string(t) for each ChartType)
const CHART_TYPE_FROM_WIRE = let d = Dict{String,ChartType}()
    for (t, w) in CHART_TYPE_WIRE
        d[w] = t
        d[string(t)] = t  # e.g. "I_MR", "Xbar_R", "p_chart"
    end
    d
end

chart_type_to_string(t::ChartType) = CHART_TYPE_WIRE[t]

function parse_chart_type(s::AbstractString)::Union{ChartType,Nothing}
    get(CHART_TYPE_FROM_WIRE, String(s), nothing)
end

# ── Subgroup size factors (HTML SS_FACTORS n=2..25) ─────────────────────
# A2/D3/D4 for X̄-R; A3/B3/B4 for X̄-S; d2 unbiases R̄→σ̂; c4 unbiases s̄→σ̂ (Cpk).
const SS_FACTORS = Dict{Int,NamedTuple{(:A2, :D3, :D4, :A3, :B3, :B4, :d2, :c4),NTuple{8,Float64}}}(
    2  => (A2 = 1.880, D3 = 0.0,   D4 = 3.267, A3 = 2.659, B3 = 0.0,   B4 = 3.267, d2 = 1.128, c4 = 0.7979),
    3  => (A2 = 1.023, D3 = 0.0,   D4 = 2.575, A3 = 1.954, B3 = 0.0,   B4 = 2.568, d2 = 1.693, c4 = 0.8862),
    4  => (A2 = 0.729, D3 = 0.0,   D4 = 2.282, A3 = 1.628, B3 = 0.0,   B4 = 2.266, d2 = 2.059, c4 = 0.9213),
    5  => (A2 = 0.577, D3 = 0.0,   D4 = 2.115, A3 = 1.427, B3 = 0.0,   B4 = 2.089, d2 = 2.326, c4 = 0.9400),
    6  => (A2 = 0.483, D3 = 0.0,   D4 = 2.004, A3 = 1.287, B3 = 0.030, B4 = 1.970, d2 = 2.534, c4 = 0.9515),
    7  => (A2 = 0.419, D3 = 0.076, D4 = 1.924, A3 = 1.182, B3 = 0.118, B4 = 1.882, d2 = 2.704, c4 = 0.9594),
    8  => (A2 = 0.373, D3 = 0.136, D4 = 1.864, A3 = 1.099, B3 = 0.185, B4 = 1.815, d2 = 2.847, c4 = 0.9650),
    9  => (A2 = 0.337, D3 = 0.184, D4 = 1.816, A3 = 1.032, B3 = 0.239, B4 = 1.761, d2 = 2.970, c4 = 0.9693),
    10 => (A2 = 0.308, D3 = 0.223, D4 = 1.777, A3 = 0.975, B3 = 0.284, B4 = 1.716, d2 = 3.078, c4 = 0.9727),
    11 => (A2 = 0.285, D3 = 0.256, D4 = 1.744, A3 = 0.927, B3 = 0.321, B4 = 1.679, d2 = 3.173, c4 = 0.9754),
    12 => (A2 = 0.266, D3 = 0.283, D4 = 1.717, A3 = 0.886, B3 = 0.354, B4 = 1.646, d2 = 3.258, c4 = 0.9776),
    13 => (A2 = 0.249, D3 = 0.307, D4 = 1.693, A3 = 0.850, B3 = 0.382, B4 = 1.618, d2 = 3.336, c4 = 0.9794),
    14 => (A2 = 0.235, D3 = 0.328, D4 = 1.672, A3 = 0.817, B3 = 0.406, B4 = 1.594, d2 = 3.407, c4 = 0.9810),
    15 => (A2 = 0.223, D3 = 0.347, D4 = 1.653, A3 = 0.789, B3 = 0.428, B4 = 1.572, d2 = 3.472, c4 = 0.9823),
    16 => (A2 = 0.212, D3 = 0.363, D4 = 1.637, A3 = 0.763, B3 = 0.448, B4 = 1.552, d2 = 3.532, c4 = 0.9835),
    17 => (A2 = 0.203, D3 = 0.378, D4 = 1.622, A3 = 0.739, B3 = 0.466, B4 = 1.534, d2 = 3.588, c4 = 0.9845),
    18 => (A2 = 0.194, D3 = 0.391, D4 = 1.608, A3 = 0.718, B3 = 0.482, B4 = 1.518, d2 = 3.640, c4 = 0.9854),
    19 => (A2 = 0.187, D3 = 0.403, D4 = 1.597, A3 = 0.698, B3 = 0.497, B4 = 1.503, d2 = 3.689, c4 = 0.9862),
    20 => (A2 = 0.180, D3 = 0.415, D4 = 1.585, A3 = 0.680, B3 = 0.510, B4 = 1.490, d2 = 3.735, c4 = 0.9869),
    21 => (A2 = 0.173, D3 = 0.425, D4 = 1.575, A3 = 0.663, B3 = 0.523, B4 = 1.477, d2 = 3.778, c4 = 0.9876),
    22 => (A2 = 0.167, D3 = 0.434, D4 = 1.566, A3 = 0.647, B3 = 0.534, B4 = 1.466, d2 = 3.819, c4 = 0.9882),
    23 => (A2 = 0.162, D3 = 0.443, D4 = 1.557, A3 = 0.633, B3 = 0.545, B4 = 1.455, d2 = 3.858, c4 = 0.9887),
    24 => (A2 = 0.157, D3 = 0.451, D4 = 1.548, A3 = 0.619, B3 = 0.555, B4 = 1.445, d2 = 3.895, c4 = 0.9892),
    25 => (A2 = 0.153, D3 = 0.459, D4 = 1.541, A3 = 0.606, B3 = 0.565, B4 = 1.435, d2 = 3.931, c4 = 0.9896),
)

"""Clamp subgroup size to HTML range [2, 25]."""
_clamp_subgroup_n(n::Int)::Int = clamp(n, 2, 25)

"""
    subgroup_means_and_ranges(values, n) -> (xbar, ranges, groups)

Consecutive complete chunks of size `n` (clamped 2..25). Incomplete tail dropped.
"""
function subgroup_means_and_ranges(values::AbstractVector{<:Real}, n::Int)
    n = _clamp_subgroup_n(n)
    vs = Float64.(values)
    xbar = Float64[]
    ranges = Float64[]
    groups = Vector{Vector{Float64}}()
    i = 1
    while i + n - 1 <= length(vs)
        g = vs[i:(i + n - 1)]
        push!(groups, g)
        push!(xbar, mean(g))
        push!(ranges, maximum(g) - minimum(g))
        i += n
    end
    return (xbar, ranges, groups)
end

"""
    subgroup_means_and_s(values, n) -> (xbar, svals, groups)

Like `subgroup_means_and_ranges` but secondary is sample std (corrected=true) per group.
"""
function subgroup_means_and_s(values::AbstractVector{<:Real}, n::Int)
    n = _clamp_subgroup_n(n)
    vs = Float64.(values)
    xbar = Float64[]
    svals = Float64[]
    groups = Vector{Vector{Float64}}()
    i = 1
    while i + n - 1 <= length(vs)
        g = vs[i:(i + n - 1)]
        push!(groups, g)
        push!(xbar, mean(g))
        push!(svals, std(g; corrected = true))
        i += n
    end
    return (xbar, svals, groups)
end

# ── Table-sourced subgroups (PR7b): group by column key, not fixed chunks ──

"""
    group_values_by_keys(values, keys) -> (groups, order)

Partition `values` by parallel `keys` in first-seen key order.
Empty keys are kept as a single group (key `\"\"`).
"""
function group_values_by_keys(
    values::AbstractVector{<:Real},
    keys::AbstractVector{<:AbstractString},
)
    length(values) == length(keys) ||
        throw(ArgumentError("values and keys must have the same length"))
    order = String[]
    buckets = Dict{String,Vector{Float64}}()
    for (v, k) in zip(values, keys)
        ks = String(k)
        if !haskey(buckets, ks)
            push!(order, ks)
            buckets[ks] = Float64[]
        end
        push!(buckets[ks], Float64(v))
    end
    groups = [buckets[k] for k in order]
    return (groups, order)
end

"""
    subgroup_means_and_ranges_from_groups(groups) -> (xbar, ranges, kept)

Stats from already-partitioned groups. Groups with length < 2 are dropped
(range undefined / not useful for X̄-R factors).
"""
function subgroup_means_and_ranges_from_groups(groups::AbstractVector{<:AbstractVector{<:Real}})
    xbar = Float64[]
    ranges = Float64[]
    kept = Vector{Vector{Float64}}()
    for g0 in groups
        g = Float64.(g0)
        length(g) < 2 && continue
        push!(kept, g)
        push!(xbar, mean(g))
        push!(ranges, maximum(g) - minimum(g))
    end
    return (xbar, ranges, kept)
end

"""
    subgroup_means_and_s_from_groups(groups) -> (xbar, svals, kept)

Like `subgroup_means_and_ranges_from_groups` but secondary is sample std (corrected=true).
"""
function subgroup_means_and_s_from_groups(groups::AbstractVector{<:AbstractVector{<:Real}})
    xbar = Float64[]
    svals = Float64[]
    kept = Vector{Vector{Float64}}()
    for g0 in groups
        g = Float64.(g0)
        length(g) < 2 && continue
        push!(kept, g)
        push!(xbar, mean(g))
        push!(svals, std(g; corrected = true))
    end
    return (xbar, svals, kept)
end

"""Median group size, clamped to [2, 25]; empty → fallback (also clamped)."""
function _effective_subgroup_n(
    groups::AbstractVector{<:AbstractVector{<:Real}},
    fallback::Int,
)::Int
    isempty(groups) && return _clamp_subgroup_n(fallback)
    sizes = sort([length(g) for g in groups])
    mid = sizes[div(length(sizes) + 1, 2)]
    return _clamp_subgroup_n(Int(mid))
end

"""Empty but valid series — always a legal ChartSpec.data."""
empty_workbench_data() = WorkbenchData(values = Float64[], cl = 0.0, sigma = 0.0)

# Per-chart state (moved early for pure context resolver to be usable in include order)
@kwdef mutable struct ChartSpec
    id::String = "CHT-" * string(rand(1000:9999))
    name::String = "Series-1"
    chart_type::ChartType = I_MR
    data::WorkbenchData = empty_workbench_data()
    viewport::Viewport = Viewport(x0 = 0, x1 = 0, ylo = 0.0, yhi = 1.0)
    usl::Union{Float64,Nothing} = nothing
    target::Union{Float64,Nothing} = nothing
    lsl::Union{Float64,Nothing} = nothing
    enabled_rules::Dict{String,Bool} = copy(DEFAULT_WECO_RULES)
    param::String = ""
    units::String = ""
    owner::String = ""
    tools::Vector{String} = String[]
    limits_mode::Symbol = :auto   # :auto | :manual
    manual_cl::Union{Float64,Nothing} = nothing
    manual_ucl::Union{Float64,Nothing} = nothing
    manual_lcl::Union{Float64,Nothing} = nothing
    subgroup_size::Int = 5
    live_enabled::Bool = true
    # Phase B (PR6): SharedTable provenance + column maps (copy-on-map into data)
    source::Symbol = :series   # :series | :table
    col_value::String = "Value"
    col_n::String = ""
    col_tool::String = "Tool"
    col_time::String = "Timestamp"
    # PR7b: optional Lot/Wafer/Chip (or Tool/Timestamp) column for table Xbar subgroups.
    # Empty → series-chunk of `subgroup_size` on materialized individuals (PR7).
    col_lot::String = ""
end

# ── SharedTable + copy-on-map materialize (PR6 / KD25) ──────────────────

"""In-memory shared tabular dataset. CSV is ingress only — never re-read on materialize."""
@kwdef mutable struct SharedTable
    columns::Vector{String} = String[]
    rows::Vector{Dict{String,String}} = Dict{String,String}[]
end

mean_or_0(vs) = isempty(vs) ? 0.0 : mean(vs)
std_or_0(vs) = length(vs) < 2 ? 0.0 : std(vs; corrected = true)

"""
    compute_chart_series(table, ch) -> (values, labels, point_meta)

Pure. Operates on the in-memory SharedTable only (no file I/O).
Filter rows by `ch.tools` when non-empty (via `ch.col_tool`); map `ch.col_value`.
When `ch.col_lot` is set, each point_meta includes `"lot"` (group key for PR7b Xbar).
"""
function compute_chart_series(table::SharedTable, ch::ChartSpec)
    values = Float64[]
    labels = String[]
    point_meta = Vector{Dict{String,String}}()
    col_v = ch.col_value
    col_t = ch.col_tool
    col_time = ch.col_time
    col_lot = ch.col_lot
    filter_tools = !isempty(ch.tools) && !isempty(col_t)
    for row in table.rows
        if filter_tools
            tool_val = get(row, col_t, "")
            if !(String(tool_val) in ch.tools)
                continue
            end
        end
        isempty(col_v) && continue
        cell = get(row, col_v, "")
        isempty(cell) && continue
        v = tryparse(Float64, cell)
        v === nothing && continue
        push!(values, Float64(v))
        lab = if !isempty(col_time)
            tcell = get(row, col_time, "")
            isempty(tcell) ? string(length(values)) : String(tcell)
        else
            string(length(values))
        end
        push!(labels, lab)
        pm = Dict{String,String}(
            "tool" => String(get(row, col_t, "")),
            "timestamp" => String(get(row, col_time, "")),
        )
        if !isempty(col_lot)
            pm["lot"] = String(get(row, col_lot, ""))
        end
        push!(point_meta, pm)
    end
    return (values, labels, point_meta)
end

"""True when materialize stored column-grouped X̄ primary (not raw individuals)."""
function _has_table_subgroups(ch::ChartSpec)::Bool
    get(ch.data.meta, "table_subgroups", false) === true
end

"""
    materialize_chart_from_table!(ch, table; show_lines=...)

Copy-on-map: compute series from in-memory table into `ch.data` (WorkbenchData).
Sets `ch.source = :table`, `ch.live_enabled = false`, resets viewport. No CSV re-read.

PR7b: when `chart_type` is Xbar_R/Xbar_S and `col_lot` is non-empty, group rows by that
column (Lot/Wafer/Tool/Timestamp/…), store subgroup means as `data.values`, and put
R or s series + `table_subgroups=true` in meta so the resolver does not re-chunk.
Otherwise individuals are stored and series-chunk math (PR7) applies at resolve time.
"""
function materialize_chart_from_table!(
    ch::ChartSpec,
    table::SharedTable;
    show_lines = nothing,
)
    values, labels, pmeta = compute_chart_series(table, ch)
    lines = show_lines === nothing ? DEFAULT_CHART_LINES : show_lines
    use_col_groups = (ch.chart_type == Xbar_R || ch.chart_type == Xbar_S) &&
                     !isempty(ch.col_lot) && !isempty(values)

    if use_col_groups
        keys = [get(pm, "lot", "") for pm in pmeta]
        groups, order = group_values_by_keys(values, keys)
        if ch.chart_type == Xbar_R
            xbar, secondary, kept = subgroup_means_and_ranges_from_groups(groups)
            sec_name = "R"
        else
            xbar, secondary, kept = subgroup_means_and_s_from_groups(groups)
            sec_name = "s"
        end
        # labels/meta only for kept groups (size ≥ 2); match first-seen order of kept keys
        kept_labels = String[]
        kept_pmeta = Dict{String,String}[]
        ki = 0
        for (g, key) in zip(groups, order)
            length(g) < 2 && continue
            ki += 1
            push!(kept_labels, isempty(key) ? "SG $ki" : key)
            push!(kept_pmeta, Dict{String,String}(
                "lot" => key,
                "is_subgroup" => "true",
                "size" => string(length(g)),
            ))
        end
        n_eff = _effective_subgroup_n(kept, ch.subgroup_size)
        ch.data = WorkbenchData(
            values = xbar,
            cl = mean_or_0(xbar),
            sigma = isempty(secondary) ? 0.0 : mean(secondary),
            meta = Dict{String,Any}(
                "labels" => kept_labels,
                "point_meta" => kept_pmeta,
                "table_subgroups" => true,
                "secondary_vals" => secondary,
                "secondary_name" => sec_name,
                "subgroup_n" => n_eff,
            ),
        )
        plot_vs = xbar
    else
        ch.data = WorkbenchData(
            values = values,
            cl = mean_or_0(values),
            sigma = std_or_0(values),
            meta = Dict{String,Any}("labels" => labels, "point_meta" => pmeta),
        )
        plot_vs = values
    end

    ch.source = :table
    ch.live_enabled = false
    n = length(plot_vs)
    if n > 0
        ch.viewport.x0 = 1
        ch.viewport.x1 = n
        if use_col_groups
            sec = get(ch.data.meta, "secondary_vals", Float64[])
            n_sg = Int(get(ch.data.meta, "subgroup_n", ch.subgroup_size))
            lz = auto_limits(
                plot_vs;
                chart_type = ch.chart_type,
                subgroup_size = n_sg,
                secondary = sec,
            )
        else
            lz = compute_limits_and_zones(plot_vs; sigma_method = :mr)
        end
        auto_fit_viewport_y!(
            ch.viewport, plot_vs, lz;
            usl = ch.usl, lsl = ch.lsl, show_lines = lines,
        )
    else
        ch.viewport.x0 = 0
        ch.viewport.x1 = 0
        ch.viewport.ylo = 0.0
        ch.viewport.yhi = 1.0
    end
    return ch
end

"""Build SharedTable from CsvParseOk-like columns + row vectors (in-memory only)."""
function shared_table_from_columns_rows(
    columns::Vector{String},
    rows::Vector{<:AbstractVector{<:AbstractString}},
)::SharedTable
    out_rows = Dict{String,String}[]
    for row in rows
        d = Dict{String,String}()
        for (i, c) in enumerate(columns)
            d[c] = i <= length(row) ? String(row[i]) : ""
        end
        push!(out_rows, d)
    end
    return SharedTable(columns = copy(columns), rows = out_rows)
end

"""Replace `m.table` from parsed CSV columns/rows (ingress only; KD25)."""
function fill_shared_table!(m, columns::Vector{String}, rows::Vector{<:AbstractVector{<:AbstractString}})
    m.table = shared_table_from_columns_rows(columns, rows)
    return m.table
end

# Chart limit-line visibility (side panel params + which lines are drawn on the plot)
const CHART_LINE_KEYS = ["cl", "sigma1", "sigma2", "sigma3", "specs"]
const CHART_LINE_LABELS = Dict(
    "cl" => "CL",
    "sigma1" => "±1σ",
    "sigma2" => "±2σ",
    "sigma3" => "±3σ",
    "specs" => "Specs",
)
const DEFAULT_CHART_LINES = Dict{String,Bool}(
    "cl" => true,
    "sigma1" => true,
    "sigma2" => true,
    "sigma3" => true,
    "specs" => true,
)

_line_on(m, key::AbstractString) = get(m.show_chart_lines, key, true)

# Per-line limit styles (solid / dotted / dashed / long_dash). Defaults match prior hardcoded look.
const LINE_STYLE_KEYS = ["solid", "dotted", "dashed", "long_dash"]
const LINE_STYLE_LABELS = Dict(
    "solid"     => "solid",
    "dotted"    => "dotted",
    "dashed"    => "dashed",
    "long_dash" => "long dash",
)
# Canvas dash / buffer step today: CL solid; σ1=2; σ2=3; σ3=4; specs=2.
const DEFAULT_CHART_LINE_STYLES = Dict{String,String}(
    "cl"     => "solid",
    "sigma1" => "dotted",     # dash/step 2
    "sigma2" => "dashed",     # dash/step 3
    "sigma3" => "long_dash",  # dash/step 4
    "specs"  => "dotted",     # dash/step 2 — MUST match current hardcoded specs
)

_line_style(m, key::AbstractString)::String =
    get(m.chart_line_styles, key, get(DEFAULT_CHART_LINE_STYLES, key, "dashed"))

"""Map style id → (canvas_dash::Union{Nothing,Int}, buffer_step::Int, buffer_ch::Char).
`canvas_dash === nothing` means solid `line!`.
Helpers own dash/step/char only; call sites keep existing tstyle(...) color mappings."""
function _style_draw_params(style::AbstractString)
    s = String(style)
    s == "solid"     && return (nothing, 1, '─')
    s == "dotted"    && return (2, 2, '-')   # legacy buffer glyph; NOT '·'
    s == "dashed"    && return (3, 3, '-')
    s == "long_dash" && return (4, 4, '-')
    return (3, 3, '-')  # defensive fallback for internal misuse only
end

function draw_limit_hline_canvas!(c, y::Int, dw::Int, style::AbstractString)
    dash, _, _ = _style_draw_params(style)
    if dash === nothing
        line!(c, 0, y, dw - 1, y)
    else
        dashed_line!(c, 0, y, dw - 1, y; dash = dash)
    end
end

function draw_limit_hline_buf!(buf, rect, val, viewport, style::AbstractString, sty)
    _, step, ch = _style_draw_params(style)
    yy = data_val_to_cell_row(Float64(val), rect, viewport)
    if step <= 1
        for xx in rect.x:right(rect)
            set_char!(buf, xx, yy, ch, sty)
        end
    else
        for xx in rect.x:right(rect)
            if (xx % step) == 0
                set_char!(buf, xx, yy, ch, sty)
            end
        end
    end
end

function _cycle_line_style!(m, key::AbstractString; dir::Int = 1)
    cur = _line_style(m, key)
    idxs = findfirst(==(cur), LINE_STYLE_KEYS)
    i = idxs === nothing ? 1 : idxs
    n = length(LINE_STYLE_KEYS)
    j = mod1(i + dir, n)
    m.chart_line_styles[key] = LINE_STYLE_KEYS[j]
    m.last_event = "style $key=$(LINE_STYLE_KEYS[j])"
    return LINE_STYLE_KEYS[j]
end

# Extensible graph visual preferences (add keys over time; panel lists VISUAL_PREF_KEYS)
const VISUAL_PREF_KEYS = ["solid_series", "solid_stroke", "braille_series", "secondary_canvas"]
const VISUAL_PREF_LABELS = Dict{String,String}(
    "solid_series" => "Dotted series (• connect)",
    "solid_stroke" => "Solid stroke (box-drawing)",
    "braille_series" => "Braille canvas line (between dots)",
    "secondary_canvas" => "Secondary canvas (MR/R/s)",
)
const DEFAULT_VISUAL_PREFS = Dict{String,Bool}(
    "solid_series" => true,
    "solid_stroke" => true,
    "braille_series" => true,
    "secondary_canvas" => true,
)

# Dual secondary canvas layout (KD-P2-15): min outer height for two stacked Blocks;
# primary/secondary height fraction when splitting the active plot rect.
const DUAL_MIN_OUTER_H = 14
const DUAL_PRIMARY_FRAC = 0.62

_pref_on(m, key::AbstractString) = get(m.visual_prefs, key, get(DEFAULT_VISUAL_PREFS, key, false))

# ── Graph presets (named snapshot of the full graph config set) ─────────
# Whole set: what is on the graph (line visibility), coloring/styles,
# series/layout visual prefs, and what WECO rules are calculated.

"""Named snapshot of graph presentation + calculation settings (no series data)."""
@kwdef mutable struct GraphPreset
    name::String = "default"
    show_chart_lines::Dict{String,Bool} = copy(DEFAULT_CHART_LINES)
    chart_line_styles::Dict{String,String} = copy(DEFAULT_CHART_LINE_STYLES)
    visual_prefs::Dict{String,Bool} = copy(DEFAULT_VISUAL_PREFS)
    enabled_rules::Dict{String,Bool} = copy(DEFAULT_WECO_RULES)
end

# ── Helpers ─────────────────────────────────────────────────────────────

function _beyond(v::Real, bound::Real, op::Function)
    op(v, bound)
end

# ── Public API ──────────────────────────────────────────────────────────

"""
    weco_detect(values, cl, sigma; enabled_rules=DEFAULT_WECO_RULES)

Full port of Western Electric rules 1-8 from the SPC workbench HTML mockup.
Returns Vector{WECOViolation} with 1-based indices.
Empty input or sigma==0 yields [] .
"""
function weco_detect(
    values::AbstractVector{<:Real},
    cl::Real,
    sigma::Real;
    enabled_rules::Dict{String,Bool} = DEFAULT_WECO_RULES,
)::Vector{WECOViolation}
    if isempty(values) || sigma == 0 || sigma === nothing
        return WECOViolation[]
    end
    vs = Float64.(values)
    n = length(vs)
    out = WECOViolation[]
    ucl3 = cl + 3 * sigma
    lcl3 = cl - 3 * sigma
    ucl2 = cl + 2 * sigma
    lcl2 = cl - 2 * sigma
    ucl1 = cl + 1 * sigma
    lcl1 = cl - 1 * sigma

    # WECO-1: 1 point beyond 3σ
    if get(enabled_rules, "WECO-1", false)
        for i in 1:n
            v = vs[i]
            if v > ucl3
                push!(out, WECOViolation("WECO-1", i, "#$i = $(round(v; digits=4)) beyond +3σ (UCL $(round(ucl3; digits=4)))"))
            elseif v < lcl3
                push!(out, WECOViolation("WECO-1", i, "#$i = $(round(v; digits=4)) beyond −3σ (LCL $(round(lcl3; digits=4)))"))
            end
        end
    end

    # WECO-2: 2 of 3 consecutive points in zone A (beyond 2σ), same side
    if get(enabled_rules, "WECO-2", false)
        for i in 3:n
            w = vs[(i-2):i]
            above = count(v -> v > ucl2, w)
            below = count(v -> v < lcl2, w)
            if above >= 2 || below >= 2
                side = above >= 2 ? "+" : "−"
                push!(out, WECOViolation("WECO-2", i, "2 of 3 ending #$i in zone A ($side 2σ side)"))
            end
        end
    end

    # WECO-3: 4 of 5 consecutive points in zone B (beyond 1σ), same side
    if get(enabled_rules, "WECO-3", false)
        for i in 5:n
            w = vs[(i-4):i]
            above = count(v -> v > ucl1, w)
            below = count(v -> v < lcl1, w)
            if above >= 4 || below >= 4
                side = above >= 4 ? "+" : "−"
                push!(out, WECOViolation("WECO-3", i, "4 of 5 ending #$i in zone B ($side 1σ side)"))
            end
        end
    end

    # WECO-4: 8 consecutive points on the same side of CL
    if get(enabled_rules, "WECO-4", false)
        for i in 8:n
            w = vs[(i-7):i]
            aboveAll = all(v -> v > cl, w)
            belowAll = all(v -> v < cl, w)
            if aboveAll || belowAll
                side = aboveAll ? "above" : "below"
                push!(out, WECOViolation("WECO-4", i, "8 in a row ending #$i $side CL"))
            end
        end
    end

    # WECO-5: 6 consecutive points trending up or down
    if get(enabled_rules, "WECO-5", false)
        for i in 6:n
            w = vs[(i-5):i]
            up = true
            down = true
            for k in 2:length(w)
                if w[k] <= w[k-1]
                    up = false
                end
                if w[k] >= w[k-1]
                    down = false
                end
            end
            if up || down
                dir = up ? "trending up" : "trending down"
                push!(out, WECOViolation("WECO-5", i, "6 in a row ending #$i $dir"))
            end
        end
    end

    # WECO-6: 14 consecutive points alternating up/down (default OFF)
    if get(enabled_rules, "WECO-6", false)
        for i in 14:n
            w = vs[(i-13):i]
            alt = true
            for k in 3:length(w)
                s1 = sign(w[k-1] - w[k-2])
                s2 = sign(w[k] - w[k-1])
                if s1 == 0 || s2 == 0 || s1 == s2
                    alt = false
                    break
                end
            end
            if alt
                push!(out, WECOViolation("WECO-6", i, "14 in a row ending #$i alternating up/down"))
            end
        end
    end

    # WECO-7: 15 consecutive points within zone C (inside 1σ) (default OFF)
    if get(enabled_rules, "WECO-7", false)
        for i in 15:n
            w = vs[(i-14):i]
            if all(v -> v < ucl1 && v > lcl1, w)
                push!(out, WECOViolation("WECO-7", i, "15 in a row ending #$i inside 1σ (over-control / stratification)"))
            end
        end
    end

    # WECO-8: 8 consecutive points outside zone C, either side (default OFF)
    if get(enabled_rules, "WECO-8", false)
        for i in 8:n
            w = vs[(i-7):i]
            if all(v -> v > ucl1 || v < lcl1, w)
                push!(out, WECOViolation("WECO-8", i, "8 in a row ending #$i outside 1σ (mixture)"))
            end
        end
    end

    out
end

"""
    compute_limits_and_zones(values; corrected=true, sigma_method=:std)

Returns LimitsAndZones with cl=mean, sigma=std(sample) or for :mr (I-MR moving range / 1.128 to match HTML autoLimits for I-MR charts).
"""
function compute_limits_and_zones(values::AbstractVector{<:Real}; corrected::Bool = true, sigma_method::Symbol = :std)::LimitsAndZones
    if isempty(values)
        z = 0.0
        return LimitsAndZones(z, z, z, z, z, z, z, z)
    end
    vs = Float64.(values)
    cl = mean(vs)
    sigma = if sigma_method == :mr && length(vs) >= 2
        mrs = [abs(vs[i] - vs[i-1]) for i in 2:length(vs)]
        mrbar = mean(mrs)
        mrbar / 1.128
    else
        std(vs; corrected = corrected)
    end
    LimitsAndZones(
        cl,
        sigma,
        cl + 3 * sigma,
        cl - 3 * sigma,
        cl + 2 * sigma,
        cl - 2 * sigma,
        cl + 1 * sigma,
        cl - 1 * sigma,
    )
end

"""
    compute_capability(values, cl, sigma; lsl=nothing, usl=nothing)

Cpk style capability (matches I-MR / variables logic from mockup).
"""
function compute_capability(
    values::AbstractVector{<:Real},
    cl::Real,
    sigma::Real;
    lsl::Union{Real,Nothing} = nothing,
    usl::Union{Real,Nothing} = nothing,
)::CapabilityResult
    if isempty(values) || sigma <= 0
        return CapabilityResult(nothing, nothing, nothing, sigma)
    end
    cpu = usl === nothing ? nothing : (usl - cl) / (3 * sigma)
    cpl = lsl === nothing ? nothing : (cl - lsl) / (3 * sigma)
    cpk = if cpu !== nothing && cpl !== nothing
        min(cpu, cpl)
    elseif cpu !== nothing
        cpu
    elseif cpl !== nothing
        cpl
    else
        nothing
    end
    CapabilityResult(cpk, cpu, cpl, sigma)
end

"""
    detect_oos(values; usl=nothing, lsl=nothing)

Returns 1-based indices of points strictly outside USL or LSL (when provided).
Distinguishes OOS (spec limits) from OOC (WECO violations).
"""
function detect_oos(
    values::AbstractVector{<:Real};
    usl::Union{Real,Nothing} = nothing,
    lsl::Union{Real,Nothing} = nothing,
)::Vector{Int}
    out = Int[]
    for (i, v) in enumerate(values)
        if (usl !== nothing && v > usl) || (lsl !== nothing && v < lsl)
            push!(out, i)
        end
    end
    out
end

# ── Y auto-fit (points + control/spec lines inside plot) ────────────────

const FIT_Y_PAD_FRAC = 0.08
const FIT_Y_PAD_ABS = 0.5

"""
    compute_fit_y_range(values, x0, x1; extras=[], pad_frac, pad_abs) -> (ylo, yhi)

Enclose all series values in the visible index window `[x0, x1]` plus any
extra levels (UCL/LCL, sigma zones, specs). Padding keeps points and lines
strictly inside the plot rather than on the edge.
"""
function compute_fit_y_range(
    values::AbstractVector{<:Real},
    x0::Int,
    x1::Int;
    extras::AbstractVector{<:Real} = Float64[],
    pad_frac::Float64 = FIT_Y_PAD_FRAC,
    pad_abs::Float64 = FIT_Y_PAD_ABS,
)::Tuple{Float64,Float64}
    lo = Inf
    hi = -Inf
    n = length(values)
    i_lo = max(1, min(x0, x1))
    i_hi = min(n, max(x0, x1))
    if n > 0 && i_lo <= i_hi
        @inbounds for i in i_lo:i_hi
            v = Float64(values[i])
            lo = min(lo, v)
            hi = max(hi, v)
        end
    end
    for e in extras
        v = Float64(e)
        isfinite(v) || continue
        lo = min(lo, v)
        hi = max(hi, v)
    end
    if !isfinite(lo) || !isfinite(hi)
        return (0.0, 1.0)
    end
    if hi == lo
        pad = max(pad_abs, abs(lo) * pad_frac, 0.5)
        return (lo - pad, hi + pad)
    end
    span = hi - lo
    pad = max(pad_abs, span * pad_frac)
    return (lo - pad, hi + pad)
end

"""
    y_extras_from_limits(lz; usl, lsl, show_lines) -> Vector{Float64}

Levels that must stay inside the plot when their chart-line toggles are on.
"""
function y_extras_from_limits(
    lz::LimitsAndZones;
    usl::Union{Real,Nothing} = nothing,
    lsl::Union{Real,Nothing} = nothing,
    show_lines::AbstractDict = DEFAULT_CHART_LINES,
)::Vector{Float64}
    extras = Float64[]
    if get(show_lines, "cl", true)
        push!(extras, lz.cl)
    end
    if get(show_lines, "sigma1", true)
        push!(extras, lz.ucl1, lz.lcl1)
    end
    if get(show_lines, "sigma2", true)
        push!(extras, lz.ucl2, lz.lcl2)
    end
    if get(show_lines, "sigma3", true)
        push!(extras, lz.ucl, lz.lcl)
    end
    if get(show_lines, "specs", true)
        usl !== nothing && isfinite(Float64(usl)) && push!(extras, Float64(usl))
        lsl !== nothing && isfinite(Float64(lsl)) && push!(extras, Float64(lsl))
    end
    extras
end

"""
    fit_viewport_y!(vp, values; x0, x1, extras, pad_frac, pad_abs)

Mutate `vp.ylo`/`vp.yhi` so the visible series (and extras) fit in the plot.
Uses `vp.x0`/`vp.x1` when `x0`/`x1` are omitted.
"""
function fit_viewport_y!(
    vp::Viewport,
    values::AbstractVector{<:Real};
    x0::Union{Int,Nothing} = nothing,
    x1::Union{Int,Nothing} = nothing,
    extras::AbstractVector{<:Real} = Float64[],
    pad_frac::Float64 = FIT_Y_PAD_FRAC,
    pad_abs::Float64 = FIT_Y_PAD_ABS,
)
    xa = x0 === nothing ? vp.x0 : x0
    xb = x1 === nothing ? vp.x1 : x1
    ylo, yhi = compute_fit_y_range(values, xa, xb; extras = extras, pad_frac = pad_frac, pad_abs = pad_abs)
    vp.ylo = ylo
    vp.yhi = yhi
    vp
end

"""
    auto_fit_viewport_y!(vp, values, lz; usl, lsl, show_lines, x0, x1)

Fit Y from visible data + enabled control/spec lines (SPC auto-scale).
"""
function auto_fit_viewport_y!(
    vp::Viewport,
    values::AbstractVector{<:Real},
    lz::LimitsAndZones;
    usl::Union{Real,Nothing} = nothing,
    lsl::Union{Real,Nothing} = nothing,
    show_lines::AbstractDict = DEFAULT_CHART_LINES,
    x0::Union{Int,Nothing} = nothing,
    x1::Union{Int,Nothing} = nothing,
    pad_frac::Float64 = FIT_Y_PAD_FRAC,
    pad_abs::Float64 = FIT_Y_PAD_ABS,
)
    extras = y_extras_from_limits(lz; usl = usl, lsl = lsl, show_lines = show_lines)
    fit_viewport_y!(vp, values; x0 = x0, x1 = x1, extras = extras, pad_frac = pad_frac, pad_abs = pad_abs)
end

"""
    cpk_band(cpk)

Returns symbol band per HTML cpkColor: :green (>=1.67), :navy (>=1.33), :amber (>=1.00), :red (<1), :none.
"""
function cpk_band(cpk::Union{Float64,Nothing})
    if cpk === nothing || (cpk isa Real && isnan(cpk))
        return :none
    end
    cpk = Float64(cpk)
    if cpk >= 1.67
        return :green
    elseif cpk >= 1.33
        return :navy
    elseif cpk >= 1.00
        return :amber
    else
        return :red
    end
end

"""
    cpk_color_for_band(band)

HTML-exact hex for swatches / Cpk text (green, navy, amber, red).
"""
function cpk_color_for_band(band::Symbol)
    if band == :green
        return "#1a6e3c"
    elseif band == :navy
        return "#1a2e5c"
    elseif band == :amber
        return "#b86000"
    elseif band == :red
        return "#c0283a"
    else
        return "#4a5568"
    end
end

# ── Centralized render context (structural fix for sigma/Cpk/OOC consistency) ──
# Always default to :mr for I-MR fidelity matching HTML autoLimits.
# Every display site (markers, hover, list, side Cpk) must use this instead of raw .data.sigma.

"""
Secondary series for dual-canvas / side stats (MR / R / s).

Values are plot-ready (I-MR: length n-1 MRs, no leading null). Limits match HTML
`autoLimits` secondary block: MR uses D4₂ (=3.267); R uses D3/D4; s uses B3/B4.
Empty when type has no secondary (attributes) or insufficient data.
"""
struct SecondarySeries
    name::String                 # "MR" | "R" | "s" | ""
    values::Vector{Float64}
    bar::Union{Float64,Nothing}  # mean of values (same as ChartRenderContext.secondary_bar)
    cl::Union{Float64,Nothing}
    ucl::Union{Float64,Nothing}
    lcl::Union{Float64,Nothing}
end

"""Empty secondary (no values / no limits). Optional name for type label continuity."""
empty_secondary_series(name::AbstractString = "") =
    SecondarySeries(String(name), Float64[], nothing, nothing, nothing, nothing)

"""
    _secondary_with_limits(name, values, chart_type, n) -> SecondarySeries

Build SecondarySeries with HTML-matching control limits from SS_FACTORS.
Degenerate bar==0 still yields cl=ucl=lcl=0 (valid). Empty values → all nothing.
"""
function _secondary_with_limits(
    name::AbstractString,
    values::Vector{Float64},
    chart_type::ChartType,
    n::Int,
)::SecondarySeries
    isempty(values) && return empty_secondary_series(name)
    bar = mean(values)
    if chart_type == I_MR
        # Moving range uses n=2 factors (HTML: UCL = 3.267·MR̄, LCL = 0)
        f = SS_FACTORS[2]
        return SecondarySeries(String(name), values, bar, bar, f.D4 * bar, 0.0)
    elseif chart_type == Xbar_R
        f = SS_FACTORS[_clamp_subgroup_n(n)]
        return SecondarySeries(String(name), values, bar, bar, f.D4 * bar, f.D3 * bar)
    elseif chart_type == Xbar_S
        f = SS_FACTORS[_clamp_subgroup_n(n)]
        return SecondarySeries(String(name), values, bar, bar, f.B4 * bar, f.B3 * bar)
    else
        return empty_secondary_series(name)
    end
end

"""
    secondary_series_for(ch, primary) -> SecondarySeries

Pure secondary series + limits for chart `ch` given its resolved primary vector.
Manual primary limits do **not** invent secondary limits — secondary is always
auto from the secondary series (HTML autoLimits secondary block is independent).
"""
function secondary_series_for(ch::ChartSpec, primary::Vector{Float64})::SecondarySeries
    if is_attribute_chart(ch.chart_type)
        return empty_secondary_series("")
    elseif _has_table_subgroups(ch) && (ch.chart_type == Xbar_R || ch.chart_type == Xbar_S)
        sec = Float64.(get(ch.data.meta, "secondary_vals", Float64[]))
        name = String(get(ch.data.meta, "secondary_name", ch.chart_type == Xbar_R ? "R" : "s"))
        n_sg = _clamp_subgroup_n(Int(get(ch.data.meta, "subgroup_n", ch.subgroup_size)))
        return _secondary_with_limits(name, sec, ch.chart_type, n_sg)
    elseif ch.chart_type == Xbar_R
        n = _clamp_subgroup_n(ch.subgroup_size)
        # Ranges from raw series chunks (not from primary means) — incomplete tail dropped
        _, ranges, _ = subgroup_means_and_ranges(ch.data.values, n)
        return _secondary_with_limits("R", ranges, Xbar_R, n)
    elseif ch.chart_type == Xbar_S
        n = _clamp_subgroup_n(ch.subgroup_size)
        _, svals, _ = subgroup_means_and_s(ch.data.values, n)
        return _secondary_with_limits("s", svals, Xbar_S, n)
    elseif ch.chart_type == I_MR
        if length(primary) < 2
            return empty_secondary_series("MR")
        end
        mrs = collect(abs.(diff(primary)))
        return _secondary_with_limits("MR", mrs, I_MR, 2)
    else
        return empty_secondary_series("")
    end
end

struct ChartRenderContext
    lz::LimitsAndZones
    viol_indices::Set{Int}
    cpk::Union{Float64,Nothing}
    band::Symbol
    # Plotted primary series (individuals for I-MR; X̄ for Xbar_R/S)
    primary_values::Vector{Float64}
    # Side-panel secondary summary (R̄ / s̄ / MR̄) — kept for compat with view/side stats
    secondary_name::String
    secondary_bar::Union{Float64,Nothing}
    # Full secondary series + control limits (P2 dual canvas; pure API in P2-PR1)
    secondary::SecondarySeries
end

"""
    _limits_from_cl_sigma(cl, sigma) -> LimitsAndZones

Zones at ±1/2/3σ of process/chart sigma. UCL/LCL = cl ± 3σ.
"""
function _limits_from_cl_sigma(cl::Float64, sigma::Float64)::LimitsAndZones
    LimitsAndZones(
        cl, sigma,
        cl + 3 * sigma, cl - 3 * sigma,
        cl + 2 * sigma, cl - 2 * sigma,
        cl + 1 * sigma, cl - 1 * sigma,
    )
end

"""
    _limits_xbar(cl, process_sigma, half_width) -> LimitsAndZones

X̄ chart: UCL/LCL from A2·R̄ or A3·s̄ (`half_width`); WECO zones from `process_sigma`
(HTML: Xbar-R σ=R̄/d2, Xbar-S σ=s̄).
"""
function _limits_xbar(cl::Float64, process_sigma::Float64, half_width::Float64)::LimitsAndZones
    LimitsAndZones(
        cl, process_sigma,
        cl + half_width, cl - half_width,
        cl + 2 * process_sigma, cl - 2 * process_sigma,
        cl + 1 * process_sigma, cl - 1 * process_sigma,
    )
end

"""
    auto_limits(values; chart_type=I_MR, subgroup_size=5, sigma_method=:mr,
                limits_mode=:auto, manual_cl=nothing, manual_ucl=nothing, manual_lcl=nothing,
                secondary=nothing)
        -> LimitsAndZones

Type-aware control limits. I_MR uses existing :mr / :std paths.
Xbar_R / Xbar_S use SS_FACTORS on consecutive series chunks (incomplete tail dropped)
unless `secondary` is provided (PR7b table-column groups): then `values` are already
subgroup means and `secondary` is the R or s series.
Attribute p/np/c/u deferred to PR8 (fall back to I_MR).
Manual kwargs reserved for PR5 (ignored here — do not rewrite manual branch).
"""

function _limits_attribute(cl::Float64, sigma::Float64, ucl::Float64, lcl::Float64)::LimitsAndZones
    LimitsAndZones(
        cl, sigma,
        ucl, lcl,
        cl + 2 * sigma, cl - 2 * sigma,
        cl + 1 * sigma, cl - 1 * sigma,
    )
end

is_attribute_chart(t::ChartType) = t == p_chart || t == np_chart || t == c_chart || t == u_chart

function auto_limits(
    values::AbstractVector{<:Real};
    chart_type::ChartType = I_MR,
    subgroup_size::Int = 5,
    sigma_method::Symbol = :mr,
    limits_mode::Symbol = :auto,
    manual_cl = nothing,
    manual_ucl = nothing,
    manual_lcl = nothing,
    secondary = nothing,
    n_bar::Union{Nothing,Real} = nothing,
)::LimitsAndZones
    # manual kwargs intentionally unused (PR5 owns manual branch in resolver)
    if chart_type == Xbar_R
        n = _clamp_subgroup_n(subgroup_size)
        if secondary === nothing
            xbar, ranges, _ = subgroup_means_and_ranges(values, n)
        else
            xbar = Float64.(values)
            ranges = Float64.(secondary)
        end
        if isempty(xbar)
            return _limits_from_cl_sigma(0.0, 0.0)
        end
        f = SS_FACTORS[n]
        cl = mean(xbar)
        rbar = mean(ranges)
        process_sigma = rbar / f.d2
        half = f.A2 * rbar
        return _limits_xbar(cl, process_sigma, half)
    elseif chart_type == Xbar_S
        n = _clamp_subgroup_n(subgroup_size)
        if secondary === nothing
            xbar, svals, _ = subgroup_means_and_s(values, n)
        else
            xbar = Float64.(values)
            svals = Float64.(secondary)
        end
        if isempty(xbar)
            return _limits_from_cl_sigma(0.0, 0.0)
        end
        f = SS_FACTORS[n]
        cl = mean(xbar)
        sbar = mean(svals)
        # HTML: out.sigma = sBar; UCL = m + A3*sBar
        half = f.A3 * sbar
        return _limits_xbar(cl, sbar, half)
    elseif chart_type == p_chart
        # HTML: pBar, sigma=sqrt(pBar*(1-pBar)/nBar), UCL=min(1,...), LCL=max(0,...)
        if isempty(values)
            return _limits_from_cl_sigma(0.0, 0.0)
        end
        p_bar = mean(Float64.(values))
        n_mean = Float64(something(n_bar, subgroup_size))
        n_mean = n_mean > 0 ? n_mean : 1.0
        sigma = sqrt(max(0.0, p_bar * (1 - p_bar) / n_mean))
        ucl = min(1.0, p_bar + 3 * sigma)
        lcl = max(0.0, p_bar - 3 * sigma)
        return _limits_attribute(p_bar, sigma, ucl, lcl)
    elseif chart_type == np_chart
        # HTML: npBar, pBar=npBar/nBar, sigma=sqrt(npBar*(1-pBar)), LCL=max(0,...)
        if isempty(values)
            return _limits_from_cl_sigma(0.0, 0.0)
        end
        np_bar = mean(Float64.(values))
        n_mean = Float64(something(n_bar, subgroup_size))
        n_mean = n_mean > 0 ? n_mean : 1.0
        p_bar = np_bar / n_mean
        sigma = sqrt(max(0.0, np_bar * (1 - p_bar)))
        ucl = np_bar + 3 * sigma
        lcl = max(0.0, np_bar - 3 * sigma)
        return _limits_attribute(np_bar, sigma, ucl, lcl)
    elseif chart_type == c_chart
        # HTML: cBar, sigma=sqrt(cBar), LCL=max(0,...)
        if isempty(values)
            return _limits_from_cl_sigma(0.0, 0.0)
        end
        c_bar = mean(Float64.(values))
        sigma = sqrt(max(0.0, c_bar))
        ucl = c_bar + 3 * sigma
        lcl = max(0.0, c_bar - 3 * sigma)
        return _limits_attribute(c_bar, sigma, ucl, lcl)
    elseif chart_type == u_chart
        # HTML: uBar, sigma=sqrt(uBar/nBar), LCL=max(0,...)
        if isempty(values)
            return _limits_from_cl_sigma(0.0, 0.0)
        end
        u_bar = mean(Float64.(values))
        n_mean = Float64(something(n_bar, subgroup_size))
        n_mean = n_mean > 0 ? n_mean : 1.0
        sigma = sqrt(max(0.0, u_bar / n_mean))
        ucl = u_bar + 3 * sigma
        lcl = max(0.0, u_bar - 3 * sigma)
        return _limits_attribute(u_bar, sigma, ucl, lcl)
    else
        # I_MR and (for now) attribute types → existing path
        return compute_limits_and_zones(values; sigma_method = sigma_method)
    end
end

"""
    _primary_and_secondary(ch) -> (primary, secondary::SecondarySeries)

Series-chunk primary for plotting/WECO; secondary series + HTML limits via
`secondary_series_for`. Side panel still uses `.name` / `.bar` (compat fields on
ChartRenderContext). Dual secondary Canvas drawing is P2-PR2 (view only).
PR7b: when `meta["table_subgroups"]`, `data.values` are already X̄ and secondary is in meta.
I_MR: primary is individuals; secondary.values are MRs length n-1.
"""
function _primary_and_secondary(ch::ChartSpec)
    vs = ch.data.values
    primary = if _has_table_subgroups(ch) && (ch.chart_type == Xbar_R || ch.chart_type == Xbar_S)
        Float64.(vs)
    elseif ch.chart_type == Xbar_R
        n = _clamp_subgroup_n(ch.subgroup_size)
        xbar, _, _ = subgroup_means_and_ranges(vs, n)
        xbar
    elseif ch.chart_type == Xbar_S
        n = _clamp_subgroup_n(ch.subgroup_size)
        xbar, _, _ = subgroup_means_and_s(vs, n)
        xbar
    else
        Float64.(vs)
    end
    sec = secondary_series_for(ch, primary)
    return (primary, sec)
end

"""
    _manual_limits_effective(ch) -> Bool

Same predicate as the resolver manual branch: mode is :manual, all three
manual_cl/ucl/lcl set, and sigma = (ucl - cl) / 3 is strictly positive.
Incomplete or non-positive-σ manual falls through to auto (badge + gateway).
"""
function _manual_limits_effective(ch::ChartSpec)::Bool
    ch.limits_mode == :manual || return false
    (ch.manual_cl === nothing || ch.manual_ucl === nothing || ch.manual_lcl === nothing) && return false
    return Float64(ch.manual_ucl) > Float64(ch.manual_cl)  # σ = (ucl-cl)/3 > 0
end

"""
    _limits_from_manual(ch) -> LimitsAndZones

HTML computeChart manual path (~2369–2371): sigma = (ucl - cl) / 3; zones from that sigma.
Uses provided CL/UCL/LCL as control limits; zone A/B/C from sigma (cl ± kσ).
Requires `_manual_limits_effective(ch)` (caller checks).
"""
function _limits_from_manual(ch::ChartSpec)::LimitsAndZones
    cl = Float64(ch.manual_cl)
    ucl = Float64(ch.manual_ucl)
    lcl = Float64(ch.manual_lcl)
    sigma = (ucl - cl) / 3
    LimitsAndZones(
        cl,
        sigma,
        ucl,
        lcl,
        cl + 2 * sigma,
        cl - 2 * sigma,
        cl + 1 * sigma,
        cl - 1 * sigma,
    )
end

"""
    resolve_chart_render_context(ch; sigma_method=:mr)

Pure resolver gateway. Returns canonical lz, WECO viol set, cpk, band, primary series,
secondary name/bar (side-panel compat), and full `SecondarySeries` (values + limits).

Manual branch (PR5): when `_manual_limits_effective` (mode + all three set + σ>0),
sigma = (ucl - cl) / 3 applies to **primary only**. Secondary limits stay auto from
the secondary series (HTML autoLimits secondary block independent of manual primary).
Auto path: PR7 type-aware auto for Xbar_R / Xbar_S (series chunks); PR7b table-column
subgroups pass precomputed secondary so means are not re-chunked; else I_MR/:mr.
"""
function resolve_chart_render_context(ch::ChartSpec; sigma_method::Symbol = :mr)::ChartRenderContext
    vs = ch.data.values
    primary, sec = _primary_and_secondary(ch)
    sec_name = sec.name
    sec_bar = sec.bar
    table_sg = _has_table_subgroups(ch)
    n_sg = if table_sg
        _clamp_subgroup_n(Int(get(ch.data.meta, "subgroup_n", ch.subgroup_size)))
    else
        _clamp_subgroup_n(ch.subgroup_size)
    end

    if _manual_limits_effective(ch)
        lz = _limits_from_manual(ch)
    elseif table_sg && (ch.chart_type == Xbar_R || ch.chart_type == Xbar_S)
        sec_vals = get(ch.data.meta, "secondary_vals", Float64[])
        lz = auto_limits(
            primary;
            chart_type = ch.chart_type,
            subgroup_size = n_sg,
            sigma_method = sigma_method,
            secondary = sec_vals,
        )
    else
        lz = auto_limits(vs; chart_type = ch.chart_type, subgroup_size = ch.subgroup_size,
                         sigma_method = sigma_method)
    end

    # WECO against primary (X̄ for subgroup charts, individuals for I-MR)
    viols = weco_detect(primary, lz.cl, lz.sigma; enabled_rules = ch.enabled_rules)
    viol_set = Set(v.index for v in viols)

    # Cpk: Xbar-S unbiases s̄ with c4 (HTML ~2388–2392); Xbar-R/I-MR already process σ̂
    cpk_sigma = if ch.chart_type == Xbar_S && sec_bar !== nothing
        c4 = SS_FACTORS[n_sg].c4
        c4 > 0 ? sec_bar / c4 : lz.sigma
    else
        lz.sigma
    end
    if is_attribute_chart(ch.chart_type)
        cpk_val = nothing
        b = :none
    else
        cr = compute_capability(primary, lz.cl, cpk_sigma; usl = ch.usl, lsl = ch.lsl)
        cpk_val = cr.cpk
        b = cpk_band(cr.cpk)
    end
    ChartRenderContext(lz, viol_set, cpk_val, b, primary, sec_name, sec_bar, sec)
end

"""
    point_status(i, ctx, ch) -> :oos | :ooc | :ok

Canonical classification for a primary-series point (index into `ctx.primary_values`).
"""
function point_status(i::Int, ctx::ChartRenderContext, ch::ChartSpec)::Symbol
    n = length(ctx.primary_values)
    if i < 1 || i > n
        return :ok
    end
    v = ctx.primary_values[i]
    if (ch.usl !== nothing && v > ch.usl) || (ch.lsl !== nothing && v < ch.lsl)
        return :oos
    elseif i in ctx.viol_indices
        return :ooc
    else
        return :ok
    end
end

"""
    generate_spc_workbench_data(n=50; seed=42, μ=0.0, σ=1.0, ooc_prob=0.05, hints=Dict())

Richer generator (seeded, supports hints for OOC/rule-triggering sequences).
Returns WorkbenchData with computed cl/sigma from produced values + meta.
"""
function generate_spc_workbench_data(
    n::Int = 50;
    seed::Int = 42,
    μ::Float64 = 0.0,
    σ::Float64 = 1.0,
    ooc_prob::Float64 = 0.05,
    hints::Dict{String,Any} = Dict{String,Any}(),
)::WorkbenchData
    rng = MersenneTwister(seed)
    vals = Float64[]
    for _ in 1:n
        v = μ + σ * randn(rng)
        if rand(rng) < ooc_prob
            v += (rand(rng) < 0.5 ? 3.5 : -3.5) * σ
        end
        push!(vals, v)
    end

    # Richer: support hints["trigger"] to force sequences that hit specific rules
    # (injects using target μ/σ; sample cl/sigma will be close for large n)
    if haskey(hints, "trigger")
        trig = string(hints["trigger"])
        if trig == "WECO-2" && n >= 3
            vals[end-2] = μ + 0.0 * σ
            vals[end-1] = μ + 2.1 * σ
            vals[end]   = μ + 2.2 * σ
        elseif trig == "WECO-5" && n >= 6
            for k in 0:5
                vals[end-5+k] = μ + (k - 2.0) * 0.8 * σ
            end
        elseif trig == "WECO-7" && n >= 15
            for k in 0:14
                vals[end-14+k] = μ + 0.05 * σ * randn(rng)
            end
        elseif trig == "WECO-4" && n >= 8
            for k in 0:7
                vals[end-7+k] = μ + 1.1 * σ
            end
        end
    end

    cl = mean(vals)
    s = std(vals; corrected = true)
    meta = Dict{String,Any}(hints)
    meta["seed"] = seed
    meta["μ_target"] = μ
    meta["σ_target"] = σ
    meta["ooc_prob"] = ooc_prob
    WorkbenchData(values = vals, cl = cl, sigma = s, meta = meta)
end

# Exports (for direct include in tests; later slices will re-export via TachikomaTUI)
export WECOViolation, WorkbenchData, LimitsAndZones, CapabilityResult
export weco_detect, compute_limits_and_zones, compute_capability, generate_spc_workbench_data
export detect_oos, cpk_band, cpk_color_for_band
export compute_fit_y_range, y_extras_from_limits, fit_viewport_y!, auto_fit_viewport_y!
export ChartRenderContext, resolve_chart_render_context, point_status, auto_limits
export SecondarySeries, secondary_series_for, empty_secondary_series
export SS_FACTORS, subgroup_means_and_ranges, subgroup_means_and_s, is_attribute_chart
export group_values_by_keys, subgroup_means_and_ranges_from_groups, subgroup_means_and_s_from_groups
export DEFAULT_WECO_RULES, DEFAULT_CHART_LINES, CHART_LINE_KEYS
export LINE_STYLE_KEYS, LINE_STYLE_LABELS, DEFAULT_CHART_LINE_STYLES
export DEFAULT_VISUAL_PREFS, VISUAL_PREF_KEYS
export GraphPreset
export ChartType, ChartSpec, empty_workbench_data, CHART_TYPE_WIRE, parse_chart_type, chart_type_to_string
export I_MR, Xbar_R, Xbar_S, p_chart, np_chart, c_chart, u_chart
export SharedTable, mean_or_0, std_or_0, compute_chart_series, materialize_chart_from_table!
export shared_table_from_columns_rows, fill_shared_table!

# UI requires Tachikoma (slices 2+). Pure tests include will pull it in.
using Tachikoma
@tachikoma_app

__precompile__(false)  # to avoid method overwrite issues from duplicated helpers

# ═══════════════════════════════════════════════════════════════════════
# From here: UI slices (2-7) — all in one file per plan. Private duplication
# of Viewport/helpers from src/spc.jl (per design decision for separation).
# Uses WorkbenchData + weco_detect / compute_* from above.
# ═══════════════════════════════════════════════════════════════════════

# ── Viewport + helpers (copied/adapted privately) ───────────────────────

"""Bresenham solid cell line (every cell filled) for dotted series connectors."""
function solid_cell_line!(buf, x0::Int, y0::Int, x1::Int, y1::Int, sty; ch::Char = '•')
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = dx + dy
    x, y = x0, y0
    while true
        set_char!(buf, x, y, ch, sty)
        (x == x1 && y == y1) && break
        e2 = 2 * err
        if e2 >= dy
            err += dy
            x += sx
        end
        if e2 <= dx
            err += dx
            y += sy
        end
    end
end

"""Pick box-drawing stroke glyph from a step (dx, dy). Terminal y grows downward."""
function _stroke_char(dx::Int, dy::Int)::Char
    if dy == 0
        return '─'
    elseif dx == 0
        return '│'
    elseif (dx > 0 && dy > 0) || (dx < 0 && dy < 0)
        return '╲'  # down-right or up-left
    else
        return '╱'  # up-right or down-left
    end
end

"""Bresenham solid stroke with box-drawing characters (─│╱╲)."""
function solid_stroke_line!(buf, x0::Int, y0::Int, x1::Int, y1::Int, sty)
    adx = abs(x1 - x0)
    ady = -abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1
    err = adx + ady
    x, y = x0, y0
    odx = x1 == x0 ? 0 : (x1 > x0 ? 1 : -1)
    ody = y1 == y0 ? 0 : (y1 > y0 ? 1 : -1)
    # paint start with overall direction
    set_char!(buf, x, y, _stroke_char(odx, ody), sty)
    while !(x == x1 && y == y1)
        e2 = 2 * err
        step_dx, step_dy = 0, 0
        if e2 >= ady
            err += ady
            x += sx
            step_dx = sx
        end
        if e2 <= adx
            err += adx
            y += sy
            step_dy = sy
        end
        set_char!(buf, x, y, _stroke_char(step_dx, step_dy), sty)
    end
end

"""Draw series connectors for a plot rect according to visual prefs (dotted and/or stroke)."""
function draw_series_connectors!(buf, plot_inner, values, vp, m)
    n = length(values)
    prev_cell = nothing
    for i in vp.x0:vp.x1
        if i < 1 || i > n
            continue
        end
        cx = data_index_to_cell(i, plot_inner, vp)
        cy = data_val_to_cell_row(values[i], plot_inner, vp)
        if prev_cell !== nothing
            if _pref_on(m, "solid_series")
                solid_cell_line!(buf, prev_cell[1], prev_cell[2], cx, cy, tstyle(:primary); ch='•')
            end
            if _pref_on(m, "solid_stroke")
                solid_stroke_line!(buf, prev_cell[1], prev_cell[2], cx, cy, tstyle(:primary, bold=true))
            end
        end
        prev_cell = (cx, cy)
    end
end

if !isdefined(@__MODULE__, :Viewport)
@kwdef mutable struct Viewport
    x0::Int = 1
    x1::Int = 1
    ylo::Float64 = 0.0
    yhi::Float64 = 1.0
end
end

const MIN_X_SPAN = 5
const MIN_Y_SPAN = 0.1

if !isdefined(@__MODULE__, :clamp_viewport!)
function clamp_viewport!(vp::Viewport, data_n::Int)
    if data_n <= 0
        vp.x0 = 0; vp.x1 = 0; vp.ylo = 0.0; vp.yhi = 0.0
        return vp
    end
    vp.x0 = clamp(vp.x0, 1, data_n)
    vp.x1 = clamp(vp.x1, 1, data_n)
    if vp.x1 - vp.x0 + 1 < MIN_X_SPAN
        mid = (vp.x0 + vp.x1) ÷ 2
        vp.x0 = max(1, mid - MIN_X_SPAN ÷ 2)
        vp.x1 = min(data_n, vp.x0 + MIN_X_SPAN - 1)
    end
    if vp.yhi - vp.ylo < MIN_Y_SPAN
        midy = (vp.ylo + vp.yhi) / 2
        vp.ylo = midy - MIN_Y_SPAN / 2
        vp.yhi = midy + MIN_Y_SPAN / 2
    end
    if vp.x0 > vp.x1
        vp.x0 = vp.x1
    end
    vp
end
end

if !isdefined(@__MODULE__, :pan_viewport!)
function pan_viewport!(vp::Viewport, dx_cells::Int, plot_w::Int, data_n::Int)
    if plot_w <= 1 || data_n <= 1
        return vp
    end
    delta = round(Int, (dx_cells / plot_w) * (vp.x1 - vp.x0))
    vp.x0 -= delta
    vp.x1 -= delta
    clamp_viewport!(vp, data_n)
    return vp
end

function zoom_viewport_around!(vp::Viewport, center_idx::Int, factor::Float64, data_n::Int)
    half = (vp.x1 - vp.x0) / 2
    new_half = max(MIN_X_SPAN / 2, half * factor)
    vp.x0 = round(Int, center_idx - new_half)
    vp.x1 = round(Int, center_idx + new_half)
    clamp_viewport!(vp, data_n)
    return vp
end

function cell_to_data_index(cell_x::Int, pa::Rect, vp::Viewport)
    pa.width <= 1 && return vp.x0
    frac = clamp((cell_x - pa.x) / (pa.width - 1), 0.0, 1.0)
    idx = vp.x0 + round(Int, frac * (vp.x1 - vp.x0))
    clamp(idx, vp.x0, vp.x1)
end
end

# WorkbenchData-specific methods (and slightly adapted helpers) — always install.
# These must not be inside the pan guard: they provide *new* dispatch targets
# (different 4th argument type) vs the SPCData versions in spc.jl.
# draw_hover_tooltip! variant also uses keyword args (extended sig).
function compute_hovered_index(evt_x::Int, evt_y::Int, pa::Rect, d::WorkbenchData, vp::Viewport)::Union{Nothing, Int}
    !contains(pa, evt_x, evt_y) && return nothing
    n = length(d.values)
    if n == 0 || vp.x1 < vp.x0
        return nothing
    end
    if vp.x1 == vp.x0
        return clamp(vp.x0, 1, n)
    end
    frac_x = clamp((evt_x - pa.x) / (pa.width - 1), 0.0, 1.0)
    target_idx = vp.x0 + frac_x * (vp.x1 - vp.x0)
    best_i = vp.x0
    best_d = Inf
    for i in vp.x0:vp.x1
        (i < 1 || i > n) && continue
        dd = abs(i - target_idx)
        if dd < best_d
            best_d = dd
            best_i = i
        end
    end
    best_i
end

function nearest_point_index_to_cell_x(cell_x::Int, pa::Rect, vp::Viewport, d::WorkbenchData)::Union{Nothing, Int}
    n = length(d.values)
    if n == 0 || vp.x1 < vp.x0
        return nothing
    end
    if vp.x1 == vp.x0
        return clamp(vp.x0, 1, n)
    end
    best_i = vp.x0
    best_d = Inf
    for i in vp.x0:vp.x1
        (i < 1 || i > n) && continue
        ci = data_index_to_cell(i, pa, vp)
        dd = abs(ci - cell_x)
        if dd < best_d
            best_d = dd
            best_i = i
        end
    end
    best_i
end

function data_index_to_cell(i::Int, pa::Rect, vp::Viewport)
    n = max(1, length(vp.x0:vp.x1))  # safe
    if pa.width <= 1 || vp.x1 == vp.x0
        return pa.x
    end
    span = vp.x1 - vp.x0
    if span <= 0
        return pa.x
    end
    frac = (i - vp.x0) / span
    x = pa.x + round(Int, frac * (pa.width - 1))
    clamp(x, pa.x, right(pa))
end

function data_val_to_cell_row(v::Float64, pa::Rect, vp::Viewport)
    if pa.height <= 1 || vp.yhi == vp.ylo
        return pa.y + pa.height ÷ 2
    end
    frac = (vp.yhi - v) / (vp.yhi - vp.ylo)
    y = pa.y + round(Int, frac * (pa.height - 1))
    clamp(y, pa.y, bottom(pa))
end

function draw_hover_tooltip!(buf, plot_inner::Rect, i::Int, v::Float64, is_viol::Bool, vp::Viewport; usl=nothing, target=nothing, lsl=nothing)
    # simple version for workbench (extended in later slices)
    hx = data_index_to_cell(i, plot_inner, vp)
    hy = data_val_to_cell_row(v, plot_inner, vp)
    val_str = "val=$(round(v;digits=2))"
    idx_str = "i=$i"
    is_oos = (usl !== nothing && v > usl) || (lsl !== nothing && v < lsl)
    stat = if is_oos
        "OOS ✗"
    elseif is_viol
        "OOC ✗"
    else
        "OK"
    end
    lines = [idx_str, val_str, stat]
    if usl !== nothing
        push!(lines, "USL=$(round(usl;digits=1))")
    end
    if lsl !== nothing
        push!(lines, "LSL=$(round(lsl;digits=1))")
    end
    tw = maximum(length, lines) + 2
    th = length(lines) + 2
    tx = hx + 2
    ty = hy - 1
    if tx + tw > right(plot_inner)
        tx = max(plot_inner.x + 1, hx - tw - 1)
    end
    if ty < plot_inner.y + 1
        ty = hy + 2
    end
    ty = clamp(ty, plot_inner.y + 1, bottom(plot_inner) - th)
    tx = clamp(tx, plot_inner.x + 1, right(plot_inner) - tw)
    b = BOX_PLAIN
    set_char!(buf, tx, ty, b.tl, tstyle(:border))
    for x in (tx+1):(tx+tw-2)
        set_char!(buf, x, ty, b.h, tstyle(:border))
    end
    set_char!(buf, tx+tw-1, ty, b.tr, tstyle(:border))
    for (li, line) in enumerate(lines)
        ry = ty + li
        set_char!(buf, tx, ry, b.v, tstyle(:border))
        set_string!(buf, tx+1, ry, " " * line * " ", tstyle(:text))
        set_char!(buf, tx+tw-1, ry, b.v, tstyle(:border))
    end
    set_char!(buf, tx, ty+th-1, b.bl, tstyle(:border))
    for x in (tx+1):(tx+tw-2)
        set_char!(buf, x, ty+th-1, b.h, tstyle(:border))
    end
    set_char!(buf, tx+tw-1, ty+th-1, b.br, tstyle(:border))
end

# (ChartSpec definition was moved earlier for pure context resolver parse order)

# ── Tool registry entry (Phase A may keep empty) ────────────────────────

@kwdef struct ToolEntry
    id::String
    description::String = ""
end

# ── Model (slice 2+) ────────────────────────────────────────────────────

@kwdef mutable struct SPCWorkbenchModel <: Model
    quit::Bool = false
    tick::Int = 0
    # Legacy single (kept for compat); primary is charts + active
    data::WorkbenchData
    viewport::Viewport = Viewport()
    hovered::Union{Nothing, Int} = nothing
    selected::Union{Nothing, Int} = nothing
    hover_x::Union{Nothing, Int} = nothing
    paused::Bool = false
    plot_area::Rect = Rect(0, 0, 0, 0)
    side_area::Rect = Rect(0, 0, 0, 0)
    drag_start::Union{Nothing, NamedTuple{(:x, :y, :vp), Tuple{Int, Int, Viewport}}} = nothing
    last_event::String = ""
    live_max::Int = 200
    rng::MersenneTwister = MersenneTwister(1234)
    current_gauge_val::Float64 = 0.0
    # Slice 4+
    config_open::Bool = false
    config_selected::Int = 1
    config_tab::Symbol = :weco   # :weco | :lines | :visual
    # Slice 5+
    usl::Union{Float64, Nothing} = nothing
    target::Union{Float64, Nothing} = nothing
    lsl::Union{Float64, Nothing} = nothing
    editing::Union{Symbol, Nothing} = nothing
    edit_buf::String = ""
    # enabled_rules: legacy mirror of active chart rules (live/config sync)
    enabled_rules::Dict{String, Bool} = copy(DEFAULT_WECO_RULES)
    # Session defaults for new charts via add_chart! (KD-P2-21); distinct from per-chart
    default_rules::Dict{String, Bool} = copy(DEFAULT_WECO_RULES)
    # Chart line visibility (CL / ±1σ / ±2σ / ±3σ / Specs)
    show_chart_lines::Dict{String, Bool} = copy(DEFAULT_CHART_LINES)
    # Per-line limit styles (solid / dotted / dashed / long_dash)
    chart_line_styles::Dict{String, String} = copy(DEFAULT_CHART_LINE_STYLES)
    # Graph visual preferences (extensible panel; start with solid series line)
    visual_prefs::Dict{String, Bool} = copy(DEFAULT_VISUAL_PREFS)
    # Named graph presets (lines + styles + visual + WECO) — session-scoped; JSON optional
    graph_presets::Vector{GraphPreset} = GraphPreset[]
    # Dashboard multi-chart (AC2/AC3)
    charts::Vector{ChartSpec} = ChartSpec[]
    active::Int = 1
    library_selected::Int = 1
    library_scroll::Int = 0
    library_area::Rect = Rect(0, 0, 0, 0)
    library_last_click::Union{Nothing, NamedTuple{(:idx, :tick), Tuple{Int, Int}}} = nothing
    view_mode::Symbol = :dashboard   # :dashboard, :focused, :help, :keymap, :library, :builder, :tools, :table, :presets, :config
    # Library / prompt SM (GC-PR2 / KD21)
    prompt_kind::Union{Nothing,Symbol} = nothing
    # :import_csv | :export_csv | :save_workbench | :load_workbench | :rename_chart
    # :filter_tool | :filter_type | :filter_owner  (GC-PR4)
    # :tool_add_id | :tool_add_desc | :tool_edit_desc  (P2-PR4 tools registry)
    # :save_graph_preset | :apply_graph_preset  (named graph config presets)
    prompt_buf::String = ""
    pending_delete::Bool = false
    # Prefill only for export prompts — never silent write to default path
    last_export_path::String = ""
    # Seed policy when charts empty — NEVER flip default from :triple
    seed_demos::Symbol = :triple     # :triple | :single | :none
    tools::Vector{ToolEntry} = ToolEntry[]
    # Tools registry UI (P2-PR4) — master list of ToolEntry; chart assign stays builder ch.tools
    tools_selected::Int = 1
    tools_scroll::Int = 0
    tools_area::Rect = Rect(0, 0, 0, 0)
    tool_pending_id::String = ""   # staged id between :tool_add_id → :tool_add_desc
    # Unified graph presets menu UI (view_mode=:presets)
    presets_selected::Int = 1
    presets_scroll::Int = 0
    presets_area::Rect = Rect(0, 0, 0, 0)
    # Prefill only for save/load prompts — never silent write to default path
    last_workbench_path::String = ""
    # Session-ephemeral dashboard/library filters (GC-PR4) — NOT in JSON schema
    filter_tool::String = ""       # empty = no filter; match requires tool in ch.tools
    filter_type::String = ""       # wire form e.g. "I-MR"; empty = no filter (NOT Union{Nothing,ChartType})
    filter_owner::String = ""      # empty = no filter; strip equality
    filter_prompt_field::Symbol = :tool  # cycle :tool → :type → :owner on each f open
    # Phase B (PR6 / KD25): in-memory SharedTable after CSV ingress
    table::SharedTable = SharedTable()
    # SharedTable grid (P2-PR7 / KD-P2-20) — keyboard-only modal
    table_row::Int = 1                 # 1-based cursor row into m.table.rows
    table_col::Int = 1                 # 1-based cursor col into m.table.columns
    table_scroll_row::Int = 0          # 0-based row window start
    table_scroll_col::Int = 0          # 0-based col window start
    table_area::Rect = Rect(0, 0, 0, 0)
    table_editing::Bool = false
    table_buf::String = ""
    # Builder form state (keyboard-only modal)
    builder_selected::Int = 1
    builder_editing::Bool = false
    builder_buf::String = ""
    # Bottom Keys panel expand (dashboard chrome; ? toggles)
    keys_panel_expanded::Bool = false
end

# ── SharedTable grid helpers (P2-PR7 / KD-P2-20) ─────────────────────────

const TABLE_MAX_RENDER_COLS = 50
const TABLE_DEFAULT_CELL_W = 12

function _table_n_rows(m::SPCWorkbenchModel)::Int
    return length(m.table.rows)
end

function _table_n_cols(m::SPCWorkbenchModel)::Int
    return min(length(m.table.columns), TABLE_MAX_RENDER_COLS)
end

"""Truncate/pad cell text to fixed display width (ASCII-oriented)."""
function _table_cell_display(s::AbstractString, w::Int)::String
    w <= 0 && return ""
    t = String(s)
    n = length(t)
    if n > w
        return w == 1 ? string(first(t)) : (first(t, w - 1) * "…")
    end
    return rpad(t, w)
end

function _table_cell_value(m::SPCWorkbenchModel, r::Int, c::Int)::String
    nr = length(m.table.rows)
    nc = length(m.table.columns)
    (r < 1 || r > nr || c < 1 || c > nc) && return ""
    col = m.table.columns[c]
    return String(get(m.table.rows[r], col, ""))
end

function _table_set_cell!(m::SPCWorkbenchModel, r::Int, c::Int, val::AbstractString)
    nr = length(m.table.rows)
    nc = length(m.table.columns)
    (r < 1 || r > nr || c < 1 || c > nc) && return
    col = m.table.columns[c]
    m.table.rows[r][col] = String(val)
    return nothing
end

"""Rows visible in grid body (title/summary/header ≈ 4; footer is mode chrome outside)."""
function _table_visible_row_capacity(m::SPCWorkbenchModel)::Int
    a = m.table_area
    (a.height <= 0 || a.width <= 0) && return 8
    return max(1, a.height - 5)
end

"""Columns visible given cell width (row index gutter 5 + separators)."""
function _table_visible_col_capacity(m::SPCWorkbenchModel; cell_w::Int = TABLE_DEFAULT_CELL_W)::Int
    a = m.table_area
    nc = _table_n_cols(m)
    nc <= 0 && return 1
    (a.width <= 0) && return min(nc, 4)
    avail = max(1, a.width - 8)  # left pad + "# " gutter
    cw = max(4, cell_w)
    return max(1, min(nc, avail ÷ (cw + 1)))
end

"""Clamp cursor and keep selection inside the scroll window."""
function _sync_table_scroll!(m::SPCWorkbenchModel;
                             row_cap::Int = _table_visible_row_capacity(m),
                             col_cap::Int = _table_visible_col_capacity(m))
    nr = length(m.table.rows)
    nc = _table_n_cols(m)
    if nr <= 0 || nc <= 0
        m.table_row = 1
        m.table_col = 1
        m.table_scroll_row = 0
        m.table_scroll_col = 0
        return
    end
    m.table_row = clamp(m.table_row, 1, nr)
    m.table_col = clamp(m.table_col, 1, nc)
    rc = max(1, row_cap)
    if m.table_row <= m.table_scroll_row
        m.table_scroll_row = m.table_row - 1
    elseif m.table_row > m.table_scroll_row + rc
        m.table_scroll_row = m.table_row - rc
    end
    m.table_scroll_row = clamp(m.table_scroll_row, 0, max(0, nr - rc))
    cc = max(1, col_cap)
    if m.table_col <= m.table_scroll_col
        m.table_scroll_col = m.table_col - 1
    elseif m.table_col > m.table_scroll_col + cc
        m.table_scroll_col = m.table_col - cc
    end
    m.table_scroll_col = clamp(m.table_scroll_col, 0, max(0, nc - cc))
    return nothing
end

"""Explicit rematerialize of active chart from SharedTable (never implicit on load)."""
function _table_rematerialize_active!(m::SPCWorkbenchModel)
    _ensure_charts!(m)
    ch = current_chart(m)
    nrows = length(m.table.rows)
    if nrows == 0
        m.last_event = "empty table — nothing to rematerialize"
        return
    end
    materialize_chart_from_table!(ch, m.table; show_lines = m.show_chart_lines)
    # Push chart → legacy mirrors (materialize owns ch.data; do NOT _sync_active_back!)
    m.data = ch.data
    m.viewport = ch.viewport
    m.usl = ch.usl
    m.target = ch.target
    m.lsl = ch.lsl
    m.enabled_rules = ch.enabled_rules
    m.last_event = "rematerialized $(length(ch.data.values)) pts from table"
    return nothing
end

function _handle_table_keys!(m::SPCWorkbenchModel, evt::KeyEvent)
    _ensure_charts!(m)
    nr = length(m.table.rows)
    nc = _table_n_cols(m)

    # Mid-edit: Esc cancel; Enter commit; printable into buf; q is literal
    if m.table_editing
        if evt.key == :escape
            m.table_editing = false
            m.table_buf = ""
            m.last_event = "cell edit cancel"
            return
        elseif evt.key == :enter
            if nr >= 1 && nc >= 1
                m.table_row = clamp(m.table_row, 1, nr)
                m.table_col = clamp(m.table_col, 1, nc)
                _table_set_cell!(m, m.table_row, m.table_col, m.table_buf)
                m.last_event = "cell set r=$(m.table_row) c=$(m.table_col)"
            else
                m.last_event = "empty table — no cell"
            end
            m.table_editing = false
            m.table_buf = ""
            return
        elseif evt.key == :backspace
            m.table_buf = isempty(m.table_buf) ? "" : chop(m.table_buf)
            m.last_event = "edit: $(m.table_buf)"
            return
        elseif evt.key == :char
            c = evt.char
            if c >= ' ' && c != '\x7f'
                m.table_buf *= string(c)
                m.last_event = "edit: $(m.table_buf)"
            end
            return
        end
        return
    end

    if evt.key == :escape || (evt.key == :char && (evt.char == 'q' || evt.char == 'Q'))
        m.view_mode = :dashboard
        m.table_editing = false
        m.table_buf = ""
        m.last_event = "table closed"
        return
    end

    if evt.key == :up
        if nr >= 1
            m.table_row = max(1, m.table_row - 1)
        end
        _sync_table_scroll!(m)
        m.last_event = "table r=$(m.table_row) c=$(m.table_col)"
        return
    elseif evt.key == :down
        if nr >= 1
            m.table_row = min(nr, m.table_row + 1)
        end
        _sync_table_scroll!(m)
        m.last_event = "table r=$(m.table_row) c=$(m.table_col)"
        return
    elseif evt.key == :left
        if nc >= 1
            m.table_col = max(1, m.table_col - 1)
        end
        _sync_table_scroll!(m)
        m.last_event = "table r=$(m.table_row) c=$(m.table_col)"
        return
    elseif evt.key == :right
        if nc >= 1
            m.table_col = min(nc, m.table_col + 1)
        end
        _sync_table_scroll!(m)
        m.last_event = "table r=$(m.table_row) c=$(m.table_col)"
        return
    elseif evt.key == :pageup
        if nr >= 1
            step = max(1, _table_visible_row_capacity(m))
            m.table_row = max(1, m.table_row - step)
        end
        _sync_table_scroll!(m)
        m.last_event = "table page up r=$(m.table_row)"
        return
    elseif evt.key == :pagedown
        if nr >= 1
            step = max(1, _table_visible_row_capacity(m))
            m.table_row = min(nr, m.table_row + step)
        end
        _sync_table_scroll!(m)
        m.last_event = "table page down r=$(m.table_row)"
        return
    elseif evt.key == :enter
        if nr < 1 || nc < 1
            m.last_event = "empty table — no cell to edit"
            return
        end
        m.table_row = clamp(m.table_row, 1, nr)
        m.table_col = clamp(m.table_col, 1, nc)
        m.table_editing = true
        m.table_buf = _table_cell_value(m, m.table_row, m.table_col)
        m.last_event = "edit cell r=$(m.table_row) c=$(m.table_col)"
        return
    elseif evt.key == :char
        c = evt.char
        if c == 'r' || c == 'R'
            # Explicit rematerialize active chart (KD-P2-18 / design: never auto on load)
            _table_rematerialize_active!(m)
            return
        end
    end
    return  # absorb other keys — no fall-through to dashboard
end

should_quit(m::SPCWorkbenchModel) = m.quit

function _boot_viewport(d::WorkbenchData; usl=nothing, lsl=nothing, show_lines=DEFAULT_CHART_LINES)
    nn = length(d.values)
    nn <= 0 && return Viewport(x0 = 0, x1 = 0, ylo = 0.0, yhi = 1.0)
    lz = compute_limits_and_zones(d.values; sigma_method = :mr)
    vp = Viewport(x0 = 1, x1 = nn)
    auto_fit_viewport_y!(vp, d.values, lz; usl = usl, lsl = lsl, show_lines = show_lines)
    return vp
end

function _normalize_seed_demos(seed::Symbol)::Symbol
    if seed === :triple || seed === :single || seed === :none
        return seed
    end
    @warn "unknown seed_demos=$(seed); treating as :triple"
    return :triple
end

function _ensure_charts!(m::SPCWorkbenchModel)
    if isempty(m.charts)
        seed = _normalize_seed_demos(m.seed_demos)
        if seed === :none
            push!(m.charts, ChartSpec(
                name = "Primary",
                data = empty_workbench_data(),
                viewport = Viewport(x0 = 0, x1 = 0, ylo = 0.0, yhi = 1.0),
                enabled_rules = copy(m.enabled_rules),
            ))
            m.active = 1
            m.library_selected = 1
        else
            # :triple (default) or :single — bootstrap from legacy data + demos
            n = max(8, length(m.data.values))
            base = if n == length(m.data.values) && !isempty(m.data.values)
                deepcopy(m.data)
            else
                generate_spc_workbench_data(n; seed=42)
            end
            push!(m.charts, ChartSpec(
                name = "Primary",
                data = base,
                viewport = _boot_viewport(base; usl = m.usl, lsl = m.lsl, show_lines = m.show_chart_lines),
                usl = m.usl, target = m.target, lsl = m.lsl,
                enabled_rules = copy(m.enabled_rules),
            ))
            if seed === :triple
                d2 = generate_spc_workbench_data(n; seed=123)
                push!(m.charts, ChartSpec(name="Secondary (demo)", data=d2,
                    viewport = _boot_viewport(d2; show_lines = m.show_chart_lines)))
                d3 = generate_spc_workbench_data(15; seed=55, μ=100.0, σ=2.0)
                push!(m.charts, ChartSpec(name="Tertiary", data=d3,
                    viewport = _boot_viewport(d3; show_lines = m.show_chart_lines)))
            end
            m.active = 1
            m.library_selected = 1
        end
    end
    ch = m.charts[clamp(m.active, 1, length(m.charts))]
    # sync legacy for any remaining direct refs in old paths / live
    m.data = ch.data
    m.viewport = ch.viewport
    m.usl = ch.usl
    m.target = ch.target
    m.lsl = ch.lsl
    m.enabled_rules = ch.enabled_rules
end

current_chart(m::SPCWorkbenchModel) = m.charts[clamp(m.active,1,length(m.charts))]

function _sync_active_back!(m::SPCWorkbenchModel)
    if !isempty(m.charts)
        idx = clamp(m.active, 1, length(m.charts))
        ch = m.charts[idx]
        ch.data = m.data
        ch.viewport = m.viewport
        ch.usl = m.usl
        ch.target = m.target
        ch.lsl = m.lsl
        ch.enabled_rules = copy(m.enabled_rules)
    end
end

# ── Graph preset capture / apply / named session store ──────────────────

"""
    capture_graph_preset(m; name="default") -> GraphPreset

Deep-copy snapshot of the whole graph config set: line visibility, line styles
(coloring/dash), visual prefs, and WECO rules from the active chart (or model
mirror when no charts).
"""
function capture_graph_preset(m::SPCWorkbenchModel; name::AbstractString = "default")::GraphPreset
    _ensure_charts!(m)
    rules = if !isempty(m.charts)
        copy(current_chart(m).enabled_rules)
    else
        copy(m.enabled_rules)
    end
    return GraphPreset(
        name = String(name),
        show_chart_lines = copy(m.show_chart_lines),
        chart_line_styles = copy(m.chart_line_styles),
        visual_prefs = copy(m.visual_prefs),
        enabled_rules = rules,
    )
end

"""
    apply_graph_preset!(m, preset) -> nothing

Apply a GraphPreset to the session: lines, styles, visual prefs, session
`default_rules`, active-chart WECO rules, and the legacy `enabled_rules` mirror.
Does not touch series data or chart metadata.
"""
function apply_graph_preset!(m::SPCWorkbenchModel, p::GraphPreset)
    _ensure_charts!(m)
    m.show_chart_lines = copy(p.show_chart_lines)
    m.chart_line_styles = copy(p.chart_line_styles)
    m.visual_prefs = copy(p.visual_prefs)
    rules = copy(p.enabled_rules)
    m.default_rules = copy(rules)
    m.enabled_rules = copy(rules)
    if !isempty(m.charts)
        ch = current_chart(m)
        ch.enabled_rules = copy(rules)
        # Keep mirror identity with active chart after seed (same as toggle path)
        m.enabled_rules = ch.enabled_rules
    end
    m.last_event = "preset applied: $(p.name)"
    return nothing
end

"""
    save_named_graph_preset!(m, name) -> nothing | String

Capture current graph set under `name` into `m.graph_presets` (upsert by name).
Empty/whitespace name → error string; model unchanged.
"""
function save_named_graph_preset!(m::SPCWorkbenchModel, name::AbstractString)::Union{Nothing,String}
    n = strip(String(name))
    isempty(n) && return "empty preset name"
    p = capture_graph_preset(m; name = n)
    for i in eachindex(m.graph_presets)
        if m.graph_presets[i].name == n
            m.graph_presets[i] = p
            m.last_event = "preset updated: $n"
            return nothing
        end
    end
    push!(m.graph_presets, p)
    m.last_event = "preset saved: $n"
    return nothing
end

"""
    apply_named_graph_preset!(m, name) -> nothing | String

Find a session preset by exact name and apply it. Missing → error string.
"""
function apply_named_graph_preset!(m::SPCWorkbenchModel, name::AbstractString)::Union{Nothing,String}
    n = strip(String(name))
    isempty(n) && return "empty preset name"
    for p in m.graph_presets
        if p.name == n
            apply_graph_preset!(m, p)
            return nothing
        end
    end
    return "preset not found: $n"
end

export capture_graph_preset, apply_graph_preset!, save_named_graph_preset!, apply_named_graph_preset!

# ── Pure chart library CRUD ─────────────────────────────────────────────

"""
    add_chart!(m; name="New chart", data=empty_workbench_data()) -> Int

Append a valid ChartSpec. Returns new 1-based index. Sets library_selected;
does not change active unless charts was empty.

Seeds `enabled_rules` from `m.default_rules` (session defaults, KD-P2-21).
Demos / `_ensure_charts!` keep explicit per-chart rules and do not use this path.
"""
function add_chart!(
    m::SPCWorkbenchModel;
    name::AbstractString = "New chart",
    data::WorkbenchData = empty_workbench_data(),
)::Int
    was_empty = isempty(m.charts)
    d = WorkbenchData(
        values = copy(data.values),
        cl = data.cl,
        sigma = data.sigma,
        meta = deepcopy(data.meta),
    )
    ch = ChartSpec(
        name = String(name),
        data = d,
        viewport = _boot_viewport(d; show_lines = m.show_chart_lines),
        enabled_rules = copy(m.default_rules),
    )
    push!(m.charts, ch)
    idx = length(m.charts)
    m.library_selected = idx
    if was_empty
        m.active = idx
        _ensure_charts!(m)  # sync legacy mirrors
    end
    return idx
end

"""
    clone_chart!(m, idx) -> Int

Deep-copy chart at idx (values/rules/specs/viewport/meta); new id; name *= \" (copy)\".
Returns new index.
"""
function clone_chart!(m::SPCWorkbenchModel, idx::Int)::Int
    n = length(m.charts)
    (idx < 1 || idx > n) && throw(BoundsError(m.charts, idx))
    src = m.charts[idx]
    d = WorkbenchData(
        values = copy(src.data.values),
        cl = src.data.cl,
        sigma = src.data.sigma,
        meta = deepcopy(src.data.meta),
    )
    vp = Viewport(x0 = src.viewport.x0, x1 = src.viewport.x1,
                  ylo = src.viewport.ylo, yhi = src.viewport.yhi)
    cloned = ChartSpec(
        id = "CHT-" * string(rand(1000:9999)),
        name = src.name * " (copy)",
        chart_type = src.chart_type,
        data = d,
        viewport = vp,
        usl = src.usl,
        target = src.target,
        lsl = src.lsl,
        enabled_rules = copy(src.enabled_rules),
        param = src.param,
        units = src.units,
        owner = src.owner,
        tools = copy(src.tools),
        limits_mode = src.limits_mode,
        manual_cl = src.manual_cl,
        manual_ucl = src.manual_ucl,
        manual_lcl = src.manual_lcl,
        subgroup_size = src.subgroup_size,
        live_enabled = src.live_enabled,
        source = src.source,
        col_value = src.col_value,
        col_n = src.col_n,
        col_tool = src.col_tool,
        col_time = src.col_time,
        col_lot = src.col_lot,
    )
    push!(m.charts, cloned)
    new_idx = length(m.charts)
    m.library_selected = new_idx
    return new_idx
end

"""
    delete_chart!(m, idx) -> Bool

Refuse if only one chart remains. Clamps active + library_selected. Returns true if deleted.
"""
function delete_chart!(m::SPCWorkbenchModel, idx::Int)::Bool
    n = length(m.charts)
    n <= 1 && return false
    (idx < 1 || idx > n) && return false
    # Persist unsynced legacy mirror edits on the current active chart before removal
    # (same pattern as set_active_chart!). Without this, delete of a *different* chart
    # would drop m.usl/target/lsl/rules via _ensure_charts! overwrite.
    _sync_active_back!(m)
    deleteat!(m.charts, idx)
    # clamp active
    if m.active > length(m.charts)
        m.active = length(m.charts)
    elseif m.active > idx
        m.active = m.active - 1
    elseif m.active == idx
        m.active = min(idx, length(m.charts))
    end
    m.active = clamp(m.active, 1, length(m.charts))
    # clamp library_selected
    if m.library_selected > length(m.charts)
        m.library_selected = length(m.charts)
    elseif m.library_selected > idx
        m.library_selected = m.library_selected - 1
    elseif m.library_selected == idx
        m.library_selected = min(idx, length(m.charts))
    end
    m.library_selected = clamp(m.library_selected, 1, length(m.charts))
    _ensure_charts!(m)  # resync legacy mirrors from new active
    # A6: under filters, absolute clamp may land on a non-matching chart — rehome
    if _any_filter_active(m)
        _rehome_active_if_filtered!(m)
    end
    return true
end

function rename_chart!(m::SPCWorkbenchModel, idx::Int, name::AbstractString)
    n = length(m.charts)
    (idx < 1 || idx > n) && throw(BoundsError(m.charts, idx))
    m.charts[idx].name = String(name)
    return nothing
end

function set_active_chart!(m::SPCWorkbenchModel, idx::Int)
    n = length(m.charts)
    n == 0 && return
    (idx < 1 || idx > n) && throw(BoundsError(m.charts, idx))
    _sync_active_back!(m)
    m.active = idx
    m.library_selected = idx
    _ensure_charts!(m)  # sync legacy mirrors from new active
    return nothing
end

# ── Tools registry pure CRUD (P2-PR4) ───────────────────────────────────
# Master list `m.tools::Vector{ToolEntry}` is distinct from per-chart `ch.tools`
# (filter assignment). Chart tool ids are assigned via builder field :tools.

"""
    add_tool!(m, id, desc="") -> Union{Int,Nothing}

Append a ToolEntry. Refuses empty id (after strip) and duplicate id
(case-sensitive). Returns new 1-based index or `nothing` on refuse.
Sets `tools_selected` to the new entry on success.
"""
function add_tool!(m::SPCWorkbenchModel, id::AbstractString, desc::AbstractString = "")::Union{Int,Nothing}
    tid = String(strip(id))
    isempty(tid) && return nothing
    any(t -> t.id == tid, m.tools) && return nothing
    push!(m.tools, ToolEntry(id = tid, description = String(strip(desc))))
    idx = length(m.tools)
    m.tools_selected = idx
    return idx
end

"""
    delete_tool!(m, idx) -> Bool

Remove tool at 1-based index. Clamps `tools_selected`. Returns true if deleted.
"""
function delete_tool!(m::SPCWorkbenchModel, idx::Int)::Bool
    n = length(m.tools)
    (idx < 1 || idx > n) && return false
    deleteat!(m.tools, idx)
    n2 = length(m.tools)
    if n2 == 0
        m.tools_selected = 1
        m.tools_scroll = 0
    else
        if m.tools_selected > n2
            m.tools_selected = n2
        elseif m.tools_selected > idx
            m.tools_selected = m.tools_selected - 1
        elseif m.tools_selected == idx
            m.tools_selected = min(idx, n2)
        end
        m.tools_selected = clamp(m.tools_selected, 1, n2)
    end
    return true
end

"""Rows available for the tools list (matches `_render_tools_page!` geometry).

Chrome: title + summary ≈ 4 top. Bottom Message|Keys lives outside `tools_area`
(content rect only). Capacity = height − 4.
"""
function _tools_visible_capacity(m::SPCWorkbenchModel)::Int
    a = m.tools_area
    h = (a.height > 0) ? a.height : 20
    return max(1, h - 4)
end

"""Keep `tools_selected` in range and `tools_scroll` so selection is visible."""
function _sync_tools_scroll!(m::SPCWorkbenchModel, ntools::Int = length(m.tools),
                             vis::Int = _tools_visible_capacity(m))
    ntools <= 0 && (m.tools_selected = 1; m.tools_scroll = 0; return)
    m.tools_selected = clamp(m.tools_selected, 1, ntools)
    sel = m.tools_selected
    max_scroll = max(0, ntools - vis)
    scroll = clamp(m.tools_scroll, 0, max_scroll)
    if sel <= scroll
        scroll = sel - 1
    elseif sel > scroll + vis
        scroll = sel - vis
    end
    m.tools_scroll = clamp(scroll, 0, max_scroll)
    return nothing
end

# ── Graph presets menu scroll helpers ───────────────────────────────────

function _presets_visible_capacity(m::SPCWorkbenchModel)::Int
    a = m.presets_area
    h = (a.height > 0) ? a.height : 20
    return max(1, h - 4)
end

function _sync_presets_scroll!(m::SPCWorkbenchModel, n::Int = length(m.graph_presets),
                              vis::Int = _presets_visible_capacity(m))
    n <= 0 && (m.presets_selected = 1; m.presets_scroll = 0; return)
    m.presets_selected = clamp(m.presets_selected, 1, n)
    sel = m.presets_selected
    max_scroll = max(0, n - vis)
    scroll = clamp(m.presets_scroll, 0, max_scroll)
    if sel <= scroll
        scroll = sel - 1
    elseif sel > scroll + vis
        scroll = sel - vis
    end
    m.presets_scroll = clamp(scroll, 0, max_scroll)
    return nothing
end

"""Open unified Graph Presets menu (from dashboard or config)."""
function _open_presets_menu!(m::SPCWorkbenchModel)
    m.view_mode = :presets
    m.config_open = false
    m.pending_delete = false
    m.prompt_kind = nothing
    m.prompt_buf = ""
    n = length(m.graph_presets)
    m.presets_selected = n >= 1 ? clamp(m.presets_selected, 1, n) : 1
    _sync_presets_scroll!(m)
    m.last_event = "presets open"
    return nothing
end

"""Open full-page Config (Rules / Lines / Visual). Forces config_open=false — no dual UI."""
function _open_config!(m::SPCWorkbenchModel; tab::Symbol = :weco)
    m.view_mode = :config
    m.config_open = false          # always clear; never dual-path (KD-UC-7)
    m.config_tab = tab
    m.config_selected = 1
    m.pending_delete = false
    m.prompt_kind = nothing
    m.prompt_buf = ""
    m.last_event = "config open $(tab)"
    return nothing
end

"""Jump section while already on Config (in-page c/v/o or Tab landing)."""
function _config_set_tab!(m::SPCWorkbenchModel, tab::Symbol)
    m.config_tab = tab
    m.config_selected = 1
    m.pending_delete = false
    m.last_event = "config tab $(tab)"
    return nothing
end

"""Apply selected session preset and return to dashboard (visible graph)."""
function _load_selected_preset!(m::SPCWorkbenchModel)::Bool
    n = length(m.graph_presets)
    if n < 1
        m.last_event = "no presets to load"
        return false
    end
    m.presets_selected = clamp(m.presets_selected, 1, n)
    p = m.graph_presets[m.presets_selected]
    apply_graph_preset!(m, p)
    m.view_mode = :dashboard
    m.prompt_kind = nothing
    m.prompt_buf = ""
    return true
end

"""Config full-page keys — only invoked while `view_mode == :config` (after prompt + pending_delete)."""
function _handle_config_keys!(m::SPCWorkbenchModel, evt::KeyEvent)
    # Close only with Esc/q (KD-UC-14) — never quit from Config
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.view_mode = :dashboard
        m.config_open = false
        m.pending_delete = false
        m.last_event = "config closed"
        return
    end
    # In-Config section jumps: c/v/o stay on Config (do NOT close)
    if evt.key == :char && (evt.char == 'c' || evt.char == 'C')
        _config_set_tab!(m, :weco)
        return
    elseif evt.key == :char && (evt.char == 'v' || evt.char == 'V')
        _config_set_tab!(m, :lines)
        return
    elseif evt.key == :char && (evt.char == 'o' || evt.char == 'O')
        _config_set_tab!(m, :visual)
        return
    end
    # Tab cycles WECO → Lines → Visual → WECO (three tabs only in PR2)
    if evt.key == :tab || (evt.key == :char && evt.char == '\t')
        next = m.config_tab == :weco ? :lines : (m.config_tab == :lines ? :visual : :weco)
        _config_set_tab!(m, next)
        return
    end
    n_items = if m.config_tab == :lines
        length(CHART_LINE_KEYS)
    elseif m.config_tab == :visual
        length(VISUAL_PREF_KEYS)
    else
        8
    end
    if evt.key == :up
        m.config_selected = max(1, m.config_selected - 1)
        m.last_event = "config up"
        return
    elseif evt.key == :down
        m.config_selected = min(n_items, m.config_selected + 1)
        m.last_event = "config down"
        return
    elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
        if m.config_tab == :lines
            key = CHART_LINE_KEYS[clamp(m.config_selected, 1, length(CHART_LINE_KEYS))]
            m.show_chart_lines[key] = !get(m.show_chart_lines, key, true)
            m.last_event = "toggle line $key"
        elseif m.config_tab == :visual
            key = VISUAL_PREF_KEYS[clamp(m.config_selected, 1, length(VISUAL_PREF_KEYS))]
            m.visual_prefs[key] = !_pref_on(m, key)
            m.last_event = "toggle visual $key"
        else
            rid = "WECO-$(m.config_selected)"
            m.enabled_rules[rid] = !get(m.enabled_rules, rid, false)
            _sync_active_back!(m)
            m.last_event = "toggle $rid"
        end
        return
    elseif evt.key == :left || evt.key == :right
        # Lines tab: cycle style; other tabs no-op (still consume — no pan while Config open)
        if m.config_tab == :lines
            key = CHART_LINE_KEYS[clamp(m.config_selected, 1, length(CHART_LINE_KEYS))]
            _cycle_line_style!(m, key; dir = evt.key == :right ? 1 : -1)
        end
        return
    elseif evt.key == :char && isdigit(evt.char)
        idx = parse(Int, string(evt.char))
        if m.config_tab == :lines
            if 1 <= idx <= length(CHART_LINE_KEYS)
                key = CHART_LINE_KEYS[idx]
                m.show_chart_lines[key] = !get(m.show_chart_lines, key, true)
                m.config_selected = idx
                m.last_event = "toggle line $key"
            end
        elseif m.config_tab == :visual
            if 1 <= idx <= length(VISUAL_PREF_KEYS)
                key = VISUAL_PREF_KEYS[idx]
                m.visual_prefs[key] = !_pref_on(m, key)
                m.config_selected = idx
                m.last_event = "toggle visual $key"
            end
        elseif 1 <= idx <= 8
            rid = "WECO-$idx"
            m.enabled_rules[rid] = !get(m.enabled_rules, rid, false)
            m.config_selected = idx
            _sync_active_back!(m)
            m.last_event = "toggle $rid"
        end
        return
    elseif evt.key == :char && (evt.char == 'S' || evt.char == 's' ||
            evt.char == 'A' || evt.char == 'a' ||
            evt.char == 'e' || evt.char == 'E')
        # PR2 transitional: preserve path to presets page (Saved lands in PR3)
        _open_presets_menu!(m)
        return
    end
    return
end

"""Graph Presets full-page keys — only invoked while `view_mode == :presets`."""
function _handle_presets_keys!(m::SPCWorkbenchModel, evt::KeyEvent)
    npre = length(m.graph_presets)
    if npre >= 1
        m.presets_selected = clamp(m.presets_selected, 1, npre)
    end
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.view_mode = :dashboard
        m.pending_delete = false
        m.last_event = "presets closed"
        return
    elseif evt.key == :up
        if npre >= 1
            m.presets_selected = max(1, m.presets_selected - 1)
        end
        _sync_presets_scroll!(m)
        m.last_event = "presets sel $(m.presets_selected)"
        return
    elseif evt.key == :down
        if npre >= 1
            m.presets_selected = min(npre, m.presets_selected + 1)
        end
        _sync_presets_scroll!(m)
        m.last_event = "presets sel $(m.presets_selected)"
        return
    elseif evt.key == :enter
        _load_selected_preset!(m)
        return
    elseif evt.key == :char
        c = evt.char
        if c == 's' || c == 'S'
            # Popup: name entry for saving current graph set
            _open_prompt!(m, :save_graph_preset; seed = "")
            return
        elseif c == 'l' || c == 'L' || c == 'a' || c == 'A'
            _load_selected_preset!(m)
            return
        elseif c == 'd' || c == 'D'
            if npre < 1
                m.last_event = "no presets to delete"
            else
                m.pending_delete = true
                m.last_event = "confirm delete preset? y/N"
            end
            return
        end
    end
    return  # absorb other keys — no fall-through
end

# ── Multi-plot pane selection + filters (GC-PR1 / GC-PR4) ───────────────

"""True when any session filter is non-empty."""
function _any_filter_active(m::SPCWorkbenchModel)::Bool
    return !isempty(m.filter_tool) || !isempty(m.filter_type) || !isempty(m.filter_owner)
end

"""True when chart matches active filters (empty filter field = pass)."""
function _chart_matches_filters(m::SPCWorkbenchModel, ch::ChartSpec)::Bool
    if !isempty(m.filter_tool)
        # LOCKED: empty ch.tools does NOT pass a non-empty tool filter
        (m.filter_tool in ch.tools) || return false
    end
    if !isempty(m.filter_type)
        chart_type_to_string(ch.chart_type) == m.filter_type || return false
    end
    if !isempty(m.filter_owner)
        # strip both sides (intentional vs bare ==): chart owner may have padding
        strip(ch.owner) == strip(m.filter_owner) || return false
    end
    return true
end

"""
    visible_charts(m) -> Vector{ChartSpec}

Charts in library order that pass `filter_tool` / `filter_type` / `filter_owner`.
Empty filters → identity (all charts, shared refs). Demo charts often have
`tools==String[]` so a non-empty tool filter yields zero matches until tools
are assigned (builder).
"""
function visible_charts(m::SPCWorkbenchModel)::Vector{ChartSpec}
    if !_any_filter_active(m)
        return m.charts
    end
    out = ChartSpec[]
    for ch in m.charts
        _chart_matches_filters(m, ch) && push!(out, ch)
    end
    return out
end

"""
A6: if active chart is filtered out, switch to first visible.
Returns `true` when `active` changed (caller must keep rehome `last_event`).
Empty visible → leave active as-is, return `false`.
"""
function _rehome_active_if_filtered!(m::SPCWorkbenchModel)::Bool
    vis = visible_charts(m)
    isempty(vis) && return false
    isempty(m.charts) && return false
    act = current_chart(m)
    any(c -> c.id == act.id, vis) && return false
    idx = findfirst(c -> c.id == vis[1].id, m.charts)
    idx === nothing && return false
    set_active_chart!(m, idx)
    m.last_event = "active chart filtered — switched to $(vis[1].name)"
    return true
end

"""Package-private. Set tool filter (stripped string); rehome with last_event precedence."""
function set_filter_tool!(m::SPCWorkbenchModel, s::AbstractString)
    m.filter_tool = String(strip(s))
    changed = _rehome_active_if_filtered!(m)
    if !changed
        if isempty(visible_charts(m)) && _any_filter_active(m)
            m.last_event = "No charts match filters"
        else
            m.last_event = isempty(m.filter_tool) ? "filter tool cleared" : "filter tool=$(m.filter_tool)"
        end
    end
    return nothing
end

"""Package-private. Set type filter as wire String (empty clears). Rehome + last_event precedence."""
function set_filter_type!(m::SPCWorkbenchModel, s::AbstractString)
    m.filter_type = String(strip(s))
    changed = _rehome_active_if_filtered!(m)
    if !changed
        if isempty(visible_charts(m)) && _any_filter_active(m)
            m.last_event = "No charts match filters"
        else
            m.last_event = isempty(m.filter_type) ? "filter type cleared" : "filter type=$(m.filter_type)"
        end
    end
    return nothing
end

"""Package-private. Set owner filter (stripped); rehome with last_event precedence."""
function set_filter_owner!(m::SPCWorkbenchModel, s::AbstractString)
    m.filter_owner = String(strip(s))
    changed = _rehome_active_if_filtered!(m)
    if !changed
        if isempty(visible_charts(m)) && _any_filter_active(m)
            m.last_event = "No charts match filters"
        else
            m.last_event = isempty(m.filter_owner) ? "filter owner cleared" : "filter owner=$(m.filter_owner)"
        end
    end
    return nothing
end

"""Package-private. Clear all three filters; cancel filter prompt if open.

After clear, every chart is visible so A6 rehome is a no-op — always set
`last_event = "filters cleared"` (no rehome branch).
"""
function clear_filters!(m::SPCWorkbenchModel)
    m.filter_tool = ""
    m.filter_type = ""
    m.filter_owner = ""
    if m.prompt_kind === :filter_tool || m.prompt_kind === :filter_type || m.prompt_kind === :filter_owner
        m.prompt_kind = nothing
        m.prompt_buf = ""
    end
    m.last_event = "filters cleared"
    return nothing
end

"""Cycle `active` among `visible_charts` by `delta` (±1). Absolute indices into `m.charts`."""
function _cycle_active_visible!(m::SPCWorkbenchModel, delta::Int)
    vis = visible_charts(m)
    if isempty(vis)
        m.last_event = "No charts match filters"
        return nothing
    end
    isempty(m.charts) && return nothing
    act = current_chart(m)
    pos = findfirst(c -> c.id == act.id, vis)
    if pos === nothing
        # Active was filtered out — land on first (forward) or last (backward)
        new_pos = delta >= 0 ? 1 : length(vis)
    else
        new_pos = clamp(pos + delta, 1, length(vis))
    end
    idx = findfirst(c -> c.id == vis[new_pos].id, m.charts)
    idx === nothing && return nothing
    set_active_chart!(m, idx)
    m.last_event = "chart $(m.active)"
    return nothing
end

"""Open next one-field filter prompt (tool→type→owner cycle). Shared by dashboard + library."""
function _open_filter_prompt_cycle!(m::SPCWorkbenchModel)
    field = m.filter_prompt_field
    if field === :type
        _open_prompt!(m, :filter_type; seed = m.filter_type)
        m.filter_prompt_field = :owner
    elseif field === :owner
        _open_prompt!(m, :filter_owner; seed = m.filter_owner)
        m.filter_prompt_field = :tool
    else
        # :tool (default) and any unknown → tool
        _open_prompt!(m, :filter_tool; seed = m.filter_tool)
        m.filter_prompt_field = :type
    end
    return nothing
end

"""Shared f/F filter keys for dashboard and library. Returns true if handled."""
function _handle_filter_char!(m::SPCWorkbenchModel, c::Char)::Bool
    if c == 'f'
        _open_filter_prompt_cycle!(m)
        return true
    elseif c == 'F'
        clear_filters!(m)
        return true
    end
    return false
end

"""
    dashboard_pane_charts(m; k=3) -> Vector{ChartSpec}

Active chart plus the next (k-1) visible neighbors. Primary interactive plot
is panes[1]; read-only extras are panes[2:end]. Fixes the hard-coded
`charts[2]`/`charts[3]` lock (active==2 duplicate / post-delete hazards).
Uses `visible_charts` (filter-aware).
"""
function dashboard_pane_charts(m::SPCWorkbenchModel; k::Int = 3)::Vector{ChartSpec}
    vis = visible_charts(m)
    isempty(vis) && return ChartSpec[]
    act = current_chart(m)
    i = findfirst(c -> c.id == act.id, vis)
    i === nothing && (i = 1)
    j = min(i + k - 1, length(vis))
    return vis[i:j]
end

export ToolEntry, add_chart!, clone_chart!, delete_chart!, rename_chart!, set_active_chart!
export visible_charts, dashboard_pane_charts
# set_filter_tool! / set_filter_type! / set_filter_owner! / clear_filters! stay package-private

# Builder form field order (P2-PR5: col maps + subgroup + owner)
const BUILDER_FIELDS = [
    :name, :chart_type, :col_value, :col_n, :col_tool, :col_time, :col_lot,
    :tools, :owner, :subgroup_size, :limits_mode,
    :manual_cl, :manual_ucl, :manual_lcl,
]
const BUILDER_FIELD_LABELS = Dict{Symbol,String}(
    :name => "Name",
    :chart_type => "Chart type",
    :col_value => "Value col",
    :col_n => "N col",
    :col_tool => "Tool col",
    :col_time => "Time col",
    :col_lot => "Lot col",
    :tools => "Tools (csv)",
    :owner => "Owner",
    :subgroup_size => "Subgroup n",
    :limits_mode => "Limits mode",
    :manual_cl => "Manual CL",
    :manual_ucl => "Manual UCL",
    :manual_lcl => "Manual LCL",
)
const _CHART_TYPE_CYCLE = ChartType[I_MR, Xbar_R, Xbar_S, p_chart, np_chart, c_chart, u_chart]

function _builder_field_value(ch::ChartSpec, field::Symbol)::String
    if field === :name
        return ch.name
    elseif field === :chart_type
        return chart_type_to_string(ch.chart_type)
    elseif field === :col_value
        return ch.col_value
    elseif field === :col_n
        return ch.col_n
    elseif field === :col_tool
        return ch.col_tool
    elseif field === :col_time
        return ch.col_time
    elseif field === :col_lot
        return ch.col_lot
    elseif field === :tools
        return join(ch.tools, ",")
    elseif field === :owner
        return ch.owner
    elseif field === :subgroup_size
        return string(ch.subgroup_size)
    elseif field === :limits_mode
        return String(ch.limits_mode)
    elseif field === :manual_cl
        return ch.manual_cl === nothing ? "" : string(ch.manual_cl)
    elseif field === :manual_ucl
        return ch.manual_ucl === nothing ? "" : string(ch.manual_ucl)
    elseif field === :manual_lcl
        return ch.manual_lcl === nothing ? "" : string(ch.manual_lcl)
    end
    return ""
end

"""
Apply builder edit buffer to chart field.
Returns event message. Invalid numeric text keeps prior value and returns `"invalid number"`.
Empty string on manual_* intentionally clears to `nothing`.
`subgroup_size` parses Int then clamps 2..25; garbage keeps prior.
"""
function _builder_apply_buf!(ch::ChartSpec, field::Symbol, buf::AbstractString)::String
    s = String(buf)
    if field === :name
        ch.name = isempty(strip(s)) ? ch.name : String(strip(s))
        return "field set"
    elseif field === :chart_type
        ct = parse_chart_type(strip(s))
        ct !== nothing && (ch.chart_type = ct)
        return "field set"
    elseif field === :col_value
        ch.col_value = String(strip(s))
        return "field set"
    elseif field === :col_n
        ch.col_n = String(strip(s))
        return "field set"
    elseif field === :col_tool
        ch.col_tool = String(strip(s))
        return "field set"
    elseif field === :col_time
        ch.col_time = String(strip(s))
        return "field set"
    elseif field === :col_lot
        ch.col_lot = String(strip(s))
        return "field set"
    elseif field === :tools
        parts = [String(strip(p)) for p in split(s, ',')]
        ch.tools = filter(!isempty, parts)
        return "field set"
    elseif field === :owner
        ch.owner = String(strip(s))
        return "field set"
    elseif field === :subgroup_size
        st = strip(s)
        v = tryparse(Int, st)
        if v === nothing
            return "invalid number"
        end
        ch.subgroup_size = _clamp_subgroup_n(v)
        return "field set"
    elseif field === :limits_mode
        ls = lowercase(strip(s))
        if ls == "manual"
            ch.limits_mode = :manual
        elseif ls == "auto"
            ch.limits_mode = :auto
        end
        return "field set"
    elseif field === :manual_cl || field === :manual_ucl || field === :manual_lcl
        st = strip(s)
        if isempty(st)
            if field === :manual_cl
                ch.manual_cl = nothing
            elseif field === :manual_ucl
                ch.manual_ucl = nothing
            else
                ch.manual_lcl = nothing
            end
            return "field set"
        end
        v = tryparse(Float64, st)
        if v === nothing
            # keep prior value — do not clear on garbage
            return "invalid number"
        end
        if field === :manual_cl
            ch.manual_cl = v
        elseif field === :manual_ucl
            ch.manual_ucl = v
        else
            ch.manual_lcl = v
        end
        return "field set"
    end
    return "field set"
end

function _builder_toggle_or_start_edit!(m::SPCWorkbenchModel, ch::ChartSpec)
    field = BUILDER_FIELDS[clamp(m.builder_selected, 1, length(BUILDER_FIELDS))]
    if field === :limits_mode
        ch.limits_mode = ch.limits_mode === :auto ? :manual : :auto
        m.last_event = "limits $(ch.limits_mode)"
        return
    elseif field === :chart_type
        idx = findfirst(==(ch.chart_type), _CHART_TYPE_CYCLE)
        idx = idx === nothing ? 1 : (idx % length(_CHART_TYPE_CYCLE)) + 1
        ch.chart_type = _CHART_TYPE_CYCLE[idx]
        m.last_event = "type $(chart_type_to_string(ch.chart_type))"
        return
    end
    m.builder_editing = true
    m.builder_buf = _builder_field_value(ch, field)
    m.last_event = "edit $(get(BUILDER_FIELD_LABELS, field, string(field)))"
end

function _builder_apply_and_materialize!(m::SPCWorkbenchModel)
    _ensure_charts!(m)
    ch = current_chart(m)
    if m.builder_editing
        field = BUILDER_FIELDS[clamp(m.builder_selected, 1, length(BUILDER_FIELDS))]
        msg = _builder_apply_buf!(ch, field, m.builder_buf)
        m.builder_editing = false
        m.builder_buf = ""
        if msg == "invalid number"
            m.last_event = msg
            return nothing  # stay in builder; do not materialize on bad number mid-edit flush
        end
    end
    nrows = length(m.table.rows)
    if nrows > 0
        materialize_chart_from_table!(ch, m.table; show_lines = m.show_chart_lines)
        m.last_event = "materialized $(length(ch.data.values)) pts from table"
    else
        m.last_event = "applied builder (empty table)"
    end
    # Push chart → legacy mirrors (materialize owns ch.data; do NOT _sync_active_back!)
    m.data = ch.data
    m.viewport = ch.viewport
    m.usl = ch.usl
    m.target = ch.target
    m.lsl = ch.lsl
    m.enabled_rules = ch.enabled_rules
    m.view_mode = :dashboard
    m.builder_editing = false
    m.builder_buf = ""
    return nothing
end

function _handle_builder_keys!(m::SPCWorkbenchModel, evt::KeyEvent)
    _ensure_charts!(m)
    ch = current_chart(m)
    nfields = length(BUILDER_FIELDS)

    # Close mode — never quit (Esc/q) when not mid-edit; mid-edit Esc cancels edit only
    if m.builder_editing
        if evt.key == :escape
            m.builder_editing = false
            m.builder_buf = ""
            m.last_event = "edit cancel"
            return
        elseif evt.key == :enter
            field = BUILDER_FIELDS[clamp(m.builder_selected, 1, nfields)]
            msg = _builder_apply_buf!(ch, field, m.builder_buf)
            m.builder_editing = false
            m.builder_buf = ""
            m.last_event = msg
            return
        elseif evt.key == :backspace
            m.builder_buf = isempty(m.builder_buf) ? "" : chop(m.builder_buf)
            m.last_event = "edit: $(m.builder_buf)"
            return
        elseif evt.key == :char
            # q during edit is literal (or we allow cancel with empty — treat as char)
            m.builder_buf *= string(evt.char)
            m.last_event = "edit: $(m.builder_buf)"
            return
        end
        return
    end

    if evt.key == :escape || (evt.key == :char && (evt.char == 'q' || evt.char == 'Q' || evt.char == 'b' || evt.char == 'B'))
        m.view_mode = :dashboard
        m.builder_editing = false
        m.builder_buf = ""
        m.last_event = "builder closed"
        return
    end

    if evt.key == :up
        m.builder_selected = max(1, m.builder_selected - 1)
        m.last_event = "builder up"
        return
    elseif evt.key == :down
        m.builder_selected = min(nfields, m.builder_selected + 1)
        m.last_event = "builder down"
        return
    elseif evt.key == :enter || (evt.key == :char && evt.char == ' ')
        _builder_toggle_or_start_edit!(m, ch)
        return
    elseif evt.key == :char
        c = evt.char
        if c == 'a' || c == 'A'
            _builder_apply_and_materialize!(m)
            return
        elseif '1' <= c <= '8'
            rid = "WECO-$(parse(Int, string(c)))"
            ch.enabled_rules[rid] = !get(ch.enabled_rules, rid, false)
            m.enabled_rules[rid] = ch.enabled_rules[rid]
            m.last_event = "toggle $rid"
            return
        elseif c == 'y' || c == 'Y'
            # cycle chart type shortcut
            idx = findfirst(==(ch.chart_type), _CHART_TYPE_CYCLE)
            idx = idx === nothing ? 1 : (idx % length(_CHART_TYPE_CYCLE)) + 1
            ch.chart_type = _CHART_TYPE_CYCLE[idx]
            m.last_event = "type $(chart_type_to_string(ch.chart_type))"
            return
        end
    end
    return
end

# ── Update (Key + Mouse, full fidelity) ─────────────────────────────────

"""Max tick delta (via re-view) between presses to count as double-click (KD-P2-19)."""
const LIBRARY_DBLCLICK_TICKS = 8

"""Rows available for the chart list (title/summary reserved; footer is mode chrome)."""
function _library_visible_capacity(m::SPCWorkbenchModel)::Int
    a = m.library_area
    h = (a.height > 0) ? a.height : 20
    # title + blank + summary + blank ≈ 4; Message|Keys chrome is outside library_area
    return max(1, h - 4)
end

"""
    _library_row_at(m, x, y) -> Union{Nothing,Int}

Hit-test library list geometry (KD-P2-19). Returns absolute index into
`m.charts`, or `nothing` if outside the list / empty / prompt / pending_delete.
List top is `library_area.y + 4` (mirrors `_render_library_page!`); indices map
through `visible_charts` then chart id → absolute index.
"""
function _library_row_at(m::SPCWorkbenchModel, x::Int, y::Int)::Union{Nothing,Int}
    m.prompt_kind !== nothing && return nothing
    m.pending_delete && return nothing

    a = m.library_area
    (a.width <= 0 || a.height <= 0) && return nothing
    !contains(a, x, y) && return nothing

    # Matches _render_library_page! list window (content rect only; chrome is separate).
    list_top = a.y + 4
    list_bottom = bottom(a)
    (y < list_top || y > list_bottom) && return nothing

    vis = visible_charts(m)
    isempty(vis) && return nothing

    vi = m.library_scroll + (y - list_top) + 1   # 1-based index into visible_charts
    (vi < 1 || vi > length(vis)) && return nothing

    return findfirst(c -> c.id == vis[vi].id, m.charts)
end

"""Library-mode mouse: single-click select, double-click activate; no dashboard pan."""
function _update_library_mouse!(m::SPCWorkbenchModel, evt::MouseEvent)
    # Never drive dashboard hover/pan from library
    m.hover_x = nothing
    m.hovered = nothing
    if evt.action == mouse_release
        m.drag_start = nothing
    end

    # prompt / pending_delete: keyboard-only (still consume mouse)
    if m.prompt_kind !== nothing || m.pending_delete
        m.last_event = string(evt.action, " ", evt.button, " (modal)")
        return
    end

    m.last_event = string(evt.action, " ", evt.button)

    if evt.action == mouse_press && evt.button == mouse_left
        abs_i = _library_row_at(m, evt.x, evt.y)
        abs_i === nothing && return

        # Double-click: same abs index within LIBRARY_DBLCLICK_TICKS (tick advances in view)
        lc = m.library_last_click
        if lc !== nothing && lc.idx == abs_i && (m.tick - lc.tick) <= LIBRARY_DBLCLICK_TICKS
            m.library_selected = abs_i
            set_active_chart!(m, abs_i)
            m.view_mode = :dashboard
            m.library_last_click = nothing
            m.last_event = "active chart $(m.active)"
            return
        end

        # Single-click select (not activate)
        m.library_selected = abs_i
        _sync_library_scroll_vis!(m, visible_charts(m))
        m.library_last_click = (idx = abs_i, tick = m.tick)
        m.last_event = "library sel $(m.library_selected)"
        return
    end
end

"""Keep `library_selected` in range and `library_scroll` so selection is visible."""
function _sync_library_scroll!(m::SPCWorkbenchModel, nch::Int = length(m.charts), vis::Int = _library_visible_capacity(m))
    vis = max(1, vis)
    if nch <= 0
        m.library_selected = 1
        m.library_scroll = 0
        return
    end
    m.library_selected = clamp(m.library_selected, 1, nch)
    sel = m.library_selected
    max_scroll = max(0, nch - vis)
    scroll = clamp(m.library_scroll, 0, max_scroll)
    if sel < scroll + 1
        scroll = sel - 1
    elseif sel > scroll + vis
        scroll = sel - vis
    end
    m.library_scroll = clamp(scroll, 0, max_scroll)
end

"""Scroll so `library_selected` stays on-screen among `vis` (visible_charts rows)."""
function _sync_library_scroll_vis!(m::SPCWorkbenchModel, vis::Vector{ChartSpec},
                                   capacity::Int = _library_visible_capacity(m))
    capacity = max(1, capacity)
    nvis = length(vis)
    nch = length(m.charts)
    if nch >= 1
        m.library_selected = clamp(m.library_selected, 1, nch)
    end
    if nvis <= 0
        m.library_scroll = 0
        return
    end
    pos = 1
    if nch >= 1
        p = findfirst(c -> c.id == m.charts[m.library_selected].id, vis)
        pos = p === nothing ? 1 : p
    end
    max_scroll = max(0, nvis - capacity)
    scroll = clamp(m.library_scroll, 0, max_scroll)
    if pos < scroll + 1
        scroll = pos - 1
    elseif pos > scroll + capacity
        scroll = pos - capacity
    end
    m.library_scroll = clamp(scroll, 0, max_scroll)
end

"""Apply prompt Enter. Rename + library I/O (GC-PR3) fully wired to master APIs."""
function _apply_prompt!(m::SPCWorkbenchModel)
    kind = m.prompt_kind
    buf = m.prompt_buf
    if kind === :rename_chart
        name = strip(buf)
        if isempty(name)
            m.last_event = "rename cancel: empty name"
        else
            nch = length(m.charts)
            if nch >= 1
                m.library_selected = clamp(m.library_selected, 1, nch)
                rename_chart!(m, m.library_selected, name)
                m.last_event = "renamed → $name"
            else
                m.last_event = "rename cancel: no charts"
            end
        end
        m.prompt_kind = nothing
        m.prompt_buf = ""
        return
    elseif kind === :import_csv
        # MUST pass library_selected — import_csv_into_model! defaults chart_idx to active
        path = strip(buf)
        nch = length(m.charts)
        if nch >= 1
            m.library_selected = clamp(m.library_selected, 1, nch)
        end
        import_csv_into_model!(m, path; chart_idx = m.library_selected)
        # last_event set by import API. On err: keep prompt open + buf so path can be edited
        # and re-Enter without re-pressing i (clearing kind would discard practical retry).
        if startswith(m.last_event, "import err:")
            return
        end
        m.prompt_kind = nothing
        return
    elseif kind === :export_csv
        path = strip(buf)
        ch = chart_for_export(m)
        err = export_csv_series(path, ch.data.values)
        if err === nothing
            m.last_export_path = path
            m.last_event = "exported $(length(ch.data.values)) values to $path"
            m.prompt_kind = nothing
        else
            # fail-closed: do not update last_export_path; keep prompt open for path retry
            m.last_event = "export err: $err"
        end
        return
    elseif kind === :save_workbench
        path = strip(buf)
        # save_workbench sets last_workbench_path + last_event only on success
        err = save_workbench(m, path)
        if err === nothing
            m.prompt_kind = nothing
        end
        # on err: keep prompt open + buf for path retry; last_workbench_path unchanged
        return
    elseif kind === :load_workbench
        path = strip(buf)
        # load_workbench!: ok → dashboard + clear prompt (io ephemerals); err → stay library
        err = load_workbench!(m, path)
        if err !== nothing
            # io clears kind on err via _set_load_err!; restore so path can be edited + re-Enter
            m.prompt_kind = :load_workbench
            # prompt_buf already kept by io
        end
        return
    elseif kind === :save_graph_preset
        name = strip(buf)
        err = save_named_graph_preset!(m, name)
        if err === nothing
            # Point selection at the saved/upserted name when in unified menu
            n = strip(String(name))
            idx = findfirst(p -> p.name == n, m.graph_presets)
            if idx !== nothing
                m.presets_selected = idx
                _sync_presets_scroll!(m)
            end
            m.prompt_kind = nothing
            m.prompt_buf = ""
        else
            m.last_event = err
            m.prompt_kind = nothing
            m.prompt_buf = ""
        end
        return
    elseif kind === :apply_graph_preset
        # Legacy name-typed apply (kept for API/tests); prefer menu Enter/l load
        name = strip(buf)
        err = apply_named_graph_preset!(m, name)
        if err === nothing
            m.prompt_kind = nothing
            m.prompt_buf = ""
            if m.view_mode === :presets
                m.view_mode = :dashboard
            end
        else
            m.last_event = err
            # keep prompt open so operator can retype name
        end
        return
    elseif kind === :filter_tool
        set_filter_tool!(m, buf)
        m.prompt_kind = nothing
        m.prompt_buf = ""
        return
    elseif kind === :filter_type
        s = strip(buf)
        if isempty(s)
            set_filter_type!(m, "")
            m.prompt_kind = nothing
            m.prompt_buf = ""
            return
        end
        parsed = parse_chart_type(s)
        if parsed === nothing
            # keep prompt open for retry; do not apply invalid type
            m.last_event = "filter type invalid: $s"
            return
        end
        # store canonical wire form only
        set_filter_type!(m, chart_type_to_string(parsed))
        m.prompt_kind = nothing
        m.prompt_buf = ""
        return
    elseif kind === :filter_owner
        set_filter_owner!(m, buf)
        m.prompt_kind = nothing
        m.prompt_buf = ""
        return
    elseif kind === :tool_add_id
        tid = strip(buf)
        if isempty(tid)
            m.last_event = "tool add cancel: empty id"
            m.prompt_kind = nothing
            m.prompt_buf = ""
            m.tool_pending_id = ""
            return
        end
        if any(t -> t.id == tid, m.tools)
            # keep prompt open for retry
            m.last_event = "tool add err: duplicate id"
            return
        end
        m.tool_pending_id = String(tid)
        m.prompt_kind = :tool_add_desc
        m.prompt_buf = ""
        m.last_event = "prompt tool_add_desc"
        return
    elseif kind === :tool_add_desc
        tid = m.tool_pending_id
        m.tool_pending_id = ""
        if isempty(strip(tid))
            m.last_event = "tool add cancel: empty id"
            m.prompt_kind = nothing
            m.prompt_buf = ""
            return
        end
        idx = add_tool!(m, tid, buf)
        if idx === nothing
            m.last_event = "tool add err: refused"
        else
            _sync_tools_scroll!(m)
            m.last_event = "added tool $(m.tools[idx].id)"
        end
        m.prompt_kind = nothing
        m.prompt_buf = ""
        return
    elseif kind === :tool_edit_desc
        ntools = length(m.tools)
        if ntools < 1
            m.last_event = "tool edit cancel: no tools"
            m.prompt_kind = nothing
            m.prompt_buf = ""
            return
        end
        m.tools_selected = clamp(m.tools_selected, 1, ntools)
        old = m.tools[m.tools_selected]
        m.tools[m.tools_selected] = ToolEntry(id = old.id, description = String(strip(buf)))
        m.last_event = "edited tool $(old.id)"
        m.prompt_kind = nothing
        m.prompt_buf = ""
        return
    else
        m.prompt_kind = nothing
        m.prompt_buf = ""
        m.last_event = "prompt cancel"
    end
end

function _open_prompt!(m::SPCWorkbenchModel, kind::Symbol; seed::AbstractString = "")
    m.prompt_kind = kind
    m.prompt_buf = String(seed)
    m.pending_delete = false
    # Clear stale dblclick so click → prompt → Esc → click cannot false-activate
    m.library_last_click = nothing
    m.last_event = "prompt $kind"
end

function update!(m::SPCWorkbenchModel, evt::KeyEvent)
    _ensure_charts!(m)
    ch = current_chart(m)
    n = length(m.data.values)

    # Builder modal — Esc/q close without quit (before global quit handler)
    if m.view_mode == :builder
        _handle_builder_keys!(m, evt)
        return
    end

    # SharedTable grid modal (P2-PR7 / KD-P2-20)
    if m.view_mode == :table
        _handle_table_keys!(m, evt)
        return
    end

    # view mode overlays (help/keymap) close on esc/q or re-toggle
    if m.view_mode == :help || m.view_mode == :keymap
        c = (evt.key == :char ? evt.char : '\0')
        if evt.key == :escape || (evt.key == :char && (evt.char == 'q' || evt.char == 'h' || evt.char == 'k' || evt.char == '?'))
            m.view_mode = :dashboard
            m.last_event = "closed overlay"
            return
        end
        return
    end

    # Config is full-page view_mode=:config (after prompt + pending_delete) — no overlay branch

    if m.editing !== nothing
        if evt.key == :char && evt.char == 'q'
            m.quit = true
            return
        end
        if evt.key == :enter
            val = tryparse(Float64, m.edit_buf)
            if val !== nothing
                if m.editing == :usl
                    m.usl = val
                elseif m.editing == :target
                    m.target = val
                elseif m.editing == :lsl
                    m.lsl = val
                end
                m.last_event = "set $(m.editing)"
                _sync_active_back!(m)
            else
                m.last_event = "edit invalid"
            end
            m.editing = nothing
            m.edit_buf = ""
            return
        elseif evt.key == :backspace
            if !isempty(m.edit_buf)
                m.edit_buf = m.edit_buf[1:end-1]
            end
            m.last_event = "edit $(m.editing): $(m.edit_buf)"
            return
        elseif evt.key == :escape
            m.editing = nothing
            m.edit_buf = ""
            m.last_event = "edit cancel"
            return
        elseif evt.key == :char && (isdigit(evt.char) || evt.char in ".-+")
            m.edit_buf *= evt.char
            m.last_event = "edit $(m.editing): $(m.edit_buf)"
            return
        end
        return
    end

    # Prompt SM (KD21): Esc cancels; q is a buffer character; never quit from prompt
    if m.prompt_kind !== nothing
        is_filter_prompt = m.prompt_kind === :filter_tool ||
                           m.prompt_kind === :filter_type ||
                           m.prompt_kind === :filter_owner
        is_tool_prompt = m.prompt_kind === :tool_add_id ||
                         m.prompt_kind === :tool_add_desc ||
                         m.prompt_kind === :tool_edit_desc
        if evt.key == :escape
            m.prompt_kind = nothing
            # Filters stay as last applied. Clear buf: next `f` reseeds from filter_*,
            # not from the cancelled edit (comment previously overpromised re-edit).
            m.prompt_buf = ""
            if is_tool_prompt
                m.tool_pending_id = ""
            end
            m.last_event = is_filter_prompt ? "filter edit cancel" : "prompt cancel"
            return
        elseif evt.key == :enter
            _apply_prompt!(m)
            return
        elseif evt.key == :backspace
            if !isempty(m.prompt_buf)
                m.prompt_buf = m.prompt_buf[1:prevind(m.prompt_buf, end)]
            end
            m.last_event = "prompt $(m.prompt_kind): $(m.prompt_buf)"
            return
        elseif evt.key == :char
            c = evt.char
            # F while in filter prompt: clear all filters + cancel prompt (GC-PR4)
            if c == 'F' && is_filter_prompt
                clear_filters!(m)
                return
            end
            if c >= ' ' && c != '\x7f'  # printable, not DEL (incl. 'q' / 'f')
                m.prompt_buf *= c
                m.last_event = "prompt $(m.prompt_kind): $(m.prompt_buf)"
            end
            return
        end
        return  # left/right and other keys: no-op under prompt
    end

    # pending_delete: y confirms; any other key (incl Esc) clears — never quit
    # Mode-local: tools → tool; presets → graph preset; library (or other) → chart.
    if m.pending_delete
        if evt.key == :char && (evt.char == 'y' || evt.char == 'Y')
            if m.view_mode == :tools
                ntools = length(m.tools)
                if ntools >= 1
                    m.tools_selected = clamp(m.tools_selected, 1, ntools)
                end
                ok = ntools >= 1 && delete_tool!(m, m.tools_selected)
                m.pending_delete = false
                _sync_tools_scroll!(m)
                m.last_event = ok ? "deleted tool" : "delete tool refused"
                return
            elseif m.view_mode == :presets
                npre = length(m.graph_presets)
                if npre >= 1
                    m.presets_selected = clamp(m.presets_selected, 1, npre)
                    deleteat!(m.graph_presets, m.presets_selected)
                    n2 = length(m.graph_presets)
                    m.presets_selected = n2 >= 1 ? clamp(m.presets_selected, 1, n2) : 1
                    _sync_presets_scroll!(m)
                    m.last_event = "deleted preset"
                else
                    m.last_event = "no presets to delete"
                end
                m.pending_delete = false
                return
            else
                nch = length(m.charts)
                if nch >= 1
                    m.library_selected = clamp(m.library_selected, 1, nch)
                end
                ok = nch >= 1 && delete_chart!(m, m.library_selected)
                m.pending_delete = false
                _sync_library_scroll!(m)
                m.last_event = ok ? "deleted chart" : "delete refused (last chart)"
                return
            end
        else
            m.pending_delete = false
            m.last_event = "delete cancelled"
            return
        end
    end

    # Library mode (before global quit — Esc/q close mode, never quit)
    # List is filter-aware: ↑↓ navigate among visible_charts absolute indices (GC-PR4).
    if m.view_mode == :library
        nch = length(m.charts)
        vis = visible_charts(m)
        nvis = length(vis)
        # Clamp once so corrupt/out-of-range selection cannot crash helpers
        if nch >= 1
            m.library_selected = clamp(m.library_selected, 1, nch)
        end
        vis_pos = 0
        if nch >= 1 && nvis > 0
            vp = findfirst(c -> c.id == m.charts[m.library_selected].id, vis)
            vis_pos = vp === nothing ? 0 : vp
        end
        if evt.key == :escape || (evt.key == :char && evt.char == 'q')
            m.view_mode = :dashboard
            m.pending_delete = false
            m.library_last_click = nothing  # prevent Esc→reopen false dblclick
            m.last_event = "library closed"
            return
        elseif evt.key == :up
            if nvis > 0
                pos = vis_pos <= 0 ? 1 : max(1, vis_pos - 1)
                ai = findfirst(c -> c.id == vis[pos].id, m.charts)
                m.library_selected = ai === nothing ? 1 : ai
            end
            _sync_library_scroll_vis!(m, vis)
            m.last_event = "library sel $(m.library_selected)"
            return
        elseif evt.key == :down
            if nvis > 0
                pos = vis_pos <= 0 ? 1 : min(nvis, vis_pos + 1)
                ai = findfirst(c -> c.id == vis[pos].id, m.charts)
                m.library_selected = ai === nothing ? 1 : ai
            end
            _sync_library_scroll_vis!(m, vis)
            m.last_event = "library sel $(m.library_selected)"
            return
        elseif evt.key == :enter
            if nvis > 0
                pos = vis_pos <= 0 ? 1 : vis_pos
                ai = findfirst(c -> c.id == vis[pos].id, m.charts)
                m.library_selected = ai === nothing ? 1 : ai
                set_active_chart!(m, m.library_selected)
                m.view_mode = :dashboard
                m.library_last_click = nothing  # exit path: clear dblclick state
                m.last_event = "active chart $(m.active)"
            else
                m.last_event = "No charts match filters"
            end
            return
        elseif evt.key == :char
            c = evt.char
            # GC-PR4: f/F filters (shared helper — must not be swallowed as library no-op)
            if _handle_filter_char!(m, c)
                return
            end
            if c == 'a' || c == 'A'
                idx = add_chart!(m)
                _sync_library_scroll!(m, length(m.charts))
                m.last_event = "added chart $idx"
                return
            elseif c == 'c' || c == 'C'
                idx = clone_chart!(m, m.library_selected)
                _sync_library_scroll!(m, length(m.charts))
                m.last_event = "cloned → $idx"
                return
            elseif c == 'd' || c == 'D'
                if nch <= 1
                    m.last_event = "cannot delete last chart"
                else
                    m.pending_delete = true
                    m.library_last_click = nothing  # keyboard-only confirm; no stale dblclick
                    m.last_event = "confirm delete? y/N"
                end
                return
            elseif c == 'n' || c == 'N'
                seed = nch >= 1 ? m.charts[m.library_selected].name : ""
                _open_prompt!(m, :rename_chart; seed = seed)
                return
            elseif c == 'i' || c == 'I'
                # GC-PR3: path prompt → import_csv_into_model!(…; chart_idx=library_selected)
                _open_prompt!(m, :import_csv; seed = "")
                return
            elseif c == 'e' || c == 'E'
                _open_prompt!(m, :export_csv; seed = m.last_export_path)
                return
            elseif c == 'w'
                _open_prompt!(m, :save_workbench; seed = m.last_workbench_path)
                return
            elseif c == 'W'
                _open_prompt!(m, :load_workbench; seed = m.last_workbench_path)
                return
            end
        end
        return  # absorb other keys (left/right pan, digits, …) — no fall-through
    end

    # Tools registry mode (P2-PR4) — Esc/q close without quit (KD21 ordering)
    if m.view_mode == :tools
        ntools = length(m.tools)
        if ntools >= 1
            m.tools_selected = clamp(m.tools_selected, 1, ntools)
        end
        if evt.key == :escape || (evt.key == :char && evt.char == 'q')
            m.view_mode = :dashboard
            m.pending_delete = false
            m.tool_pending_id = ""
            m.last_event = "tools closed"
            return
        elseif evt.key == :up
            if ntools >= 1
                m.tools_selected = max(1, m.tools_selected - 1)
            end
            _sync_tools_scroll!(m)
            m.last_event = "tools sel $(m.tools_selected)"
            return
        elseif evt.key == :down
            if ntools >= 1
                m.tools_selected = min(ntools, m.tools_selected + 1)
            end
            _sync_tools_scroll!(m)
            m.last_event = "tools sel $(m.tools_selected)"
            return
        elseif evt.key == :enter
            # Optional: apply selected id as filter_tool and return to dashboard
            if ntools >= 1
                m.tools_selected = clamp(m.tools_selected, 1, ntools)
                set_filter_tool!(m, m.tools[m.tools_selected].id)
                m.view_mode = :dashboard
            else
                m.last_event = "no tools in registry"
            end
            return
        elseif evt.key == :char
            c = evt.char
            if c == 'a' || c == 'A'
                m.tool_pending_id = ""
                _open_prompt!(m, :tool_add_id; seed = "")
                return
            elseif c == 'n' || c == 'N'
                if ntools < 1
                    m.last_event = "no tools to edit"
                else
                    m.tools_selected = clamp(m.tools_selected, 1, ntools)
                    seed = m.tools[m.tools_selected].description
                    _open_prompt!(m, :tool_edit_desc; seed = seed)
                end
                return
            elseif c == 'd' || c == 'D'
                if ntools < 1
                    m.last_event = "no tools to delete"
                else
                    m.pending_delete = true
                    m.last_event = "confirm delete tool? y/N"
                end
                return
            end
        end
        return  # absorb other keys — no fall-through
    end

    # Full-page Config (Rules/Lines/Visual) — after prompt + pending_delete (KD-UC-7/14)
    if m.view_mode == :config
        _handle_config_keys!(m, evt)
        return
    end

    # Unified Graph Presets menu — Esc/q close without quit (PR2 bridge; folds into Config Saved in PR3)
    if m.view_mode == :presets
        _handle_presets_keys!(m, evt)
        return
    end

    # Global quit (dashboard only — modes already returned above)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end

    if evt.key == :char
        c = evt.char
        if c == 'm' || c == 'M'
            # Open chart library (GC-PR2)
            m.view_mode = :library
            m.library_selected = clamp(m.active, 1, max(1, length(m.charts)))
            m.pending_delete = false
            m.prompt_kind = nothing
            m.library_last_click = nothing  # fresh open: no stale dblclick from prior session
            _sync_library_scroll!(m)
            m.last_event = "library open"
            return
        elseif c == 'x' || c == 'X'
            # Open tools registry (P2-PR4 / KD-P2-6)
            m.view_mode = :tools
            ntools = length(m.tools)
            m.tools_selected = ntools >= 1 ? clamp(m.tools_selected, 1, ntools) : 1
            m.pending_delete = false
            m.prompt_kind = nothing
            m.tool_pending_id = ""
            _sync_tools_scroll!(m)
            m.last_event = "tools open"
            return
        elseif c == 'e' || c == 'E'
            # Unified graph presets menu (save popup + load selected)
            _open_presets_menu!(m)
            return
        elseif c == 'd' || c == 'D'
            # SharedTable grid (P2-PR7 / KD-P2-20) — dashboard only; library/tools keep d=delete
            m.view_mode = :table
            m.table_editing = false
            m.table_buf = ""
            m.prompt_kind = nothing
            m.pending_delete = false
            _sync_table_scroll!(m)
            m.last_event = "table open"
            return
        elseif _handle_filter_char!(m, c)
            # GC-PR4: f cycles filter prompt; F clears all (dashboard)
            return
        elseif c == 'p' || c == 'P'
            m.paused = !m.paused
            m.last_event = m.paused ? "paused" : "resumed"
        elseif c == 'r' || c == 'R' || c == 'z' || c == 'Z'
            if n <= 0
                m.viewport.x0 = 0
                m.viewport.x1 = 0
                m.viewport.ylo = 0.0
                m.viewport.yhi = 0.0
            else
                m.viewport.x0 = 1
                m.viewport.x1 = n
                lz_r = compute_limits_and_zones(m.data.values; sigma_method = :mr)
                auto_fit_viewport_y!(m.viewport, m.data.values, lz_r;
                    usl = m.usl, lsl = m.lsl, show_lines = m.show_chart_lines)
                clamp_viewport!(m.viewport, n)
            end
            m.hovered = nothing
            m.selected = nothing
            m.hover_x = nothing
            m.drag_start = nothing
            m.last_event = "reset"
            _sync_active_back!(m)
        elseif c == 'c' || c == 'C'
            # Open Config → Rules (open only — no toggle-off; KD-UC-14)
            _open_config!(m; tab = :weco)
            return
        elseif c == 'v' || c == 'V'
            # Open Config → Lines
            _open_config!(m; tab = :lines)
            return
        elseif c == 'o' || c == 'O'
            # Open Config → Visual
            _open_config!(m; tab = :visual)
            return
        elseif c == 'u' || c == 'U'
            m.editing = :usl
            m.edit_buf = m.usl === nothing ? "" : string(m.usl)
            m.last_event = "edit usl: $(m.edit_buf)"
            return
        elseif c == 't' || c == 'T'
            m.editing = :target
            m.edit_buf = m.target === nothing ? "" : string(m.target)
            m.last_event = "edit target: $(m.edit_buf)"
            return
        elseif c == 'l' || c == 'L'
            m.editing = :lsl
            m.edit_buf = m.lsl === nothing ? "" : string(m.lsl)
            m.last_event = "edit lsl: $(m.edit_buf)"
            return
        elseif c == 'g' || c == 'G'
            # PR3: per-chart live toggle (NOT L — L remains LSL)
            chg = current_chart(m)
            chg.live_enabled = !chg.live_enabled
            m.last_event = chg.live_enabled ? "live on" : "live off"
            return
        elseif c == 's' || c == 'S'
            m.usl = m.target = m.lsl = nothing
            ch.usl = ch.target = ch.lsl = nothing
            m.last_event = "specs cleared"
            return
        elseif '1' <= c <= '8'
            rid = "WECO-$(parse(Int, string(c)))"
            m.enabled_rules[rid] = !get(m.enabled_rules, rid, false)
            ch.enabled_rules[rid] = m.enabled_rules[rid]
            m.last_event = "toggle $rid"
        elseif c == '?'
            # Toggle bottom Keys panel expand (does not open full-page help)
            m.keys_panel_expanded = !m.keys_panel_expanded
            m.last_event = m.keys_panel_expanded ? "keys expanded" : "keys collapsed"
            return
        elseif c == 'h' || c == 'H'
            m.view_mode = :help
            m.last_event = "help open"
            return
        elseif c == 'k' || c == 'K'
            m.view_mode = :keymap
            m.last_event = "keymap open"
            return
        elseif c == 'b' || c == 'B'
            # PR6: open chart builder for active chart (manual limits + mapping)
            m.view_mode = :builder
            m.builder_selected = 1
            m.builder_editing = false
            m.builder_buf = ""
            m.last_event = "builder open"
            return
        elseif c == ']' || c == '>'
            # GC-PR4: step only among visible_charts (absolute indices)
            _cycle_active_visible!(m, +1)
            return
        elseif c == '[' || c == '<'
            _cycle_active_visible!(m, -1)
            return
        end
        _sync_active_back!(m)
    end

    if evt.key == :left
        if n > 0
            m.viewport.x0 = max(1, m.viewport.x0 - 2)
            m.viewport.x1 = max(m.viewport.x0 + MIN_X_SPAN - 1, m.viewport.x1 - 2)
            clamp_viewport!(m.viewport, n)
        end
    elseif evt.key == :right
        if n > 0
            m.viewport.x1 = min(n, m.viewport.x1 + 2)
            m.viewport.x0 = min(m.viewport.x0 + 2, m.viewport.x1 - MIN_X_SPAN + 1)
            clamp_viewport!(m.viewport, n)
        end
    end
end

function update!(m::SPCWorkbenchModel, evt::MouseEvent)
    _ensure_charts!(m)
    # Library: hit-test select / double-click activate (KD-P2-19); not blanket keyboard-only
    if m.view_mode == :library
        _update_library_mouse!(m, evt)
        return
    end
    # Modal / tools / table / presets / config / prompt / pending_delete: keyboard-only (KD16)
    if m.config_open || m.editing !== nothing ||
       m.view_mode == :help || m.view_mode == :keymap ||
       m.view_mode == :builder ||
       m.view_mode == :tools ||
       m.view_mode == :table ||
       m.view_mode == :presets ||
       m.view_mode == :config ||
       m.prompt_kind !== nothing || m.pending_delete
        m.last_event = string(evt.action, " ", evt.button, " (modal)")
        m.hover_x = nothing
        m.hovered = nothing
        if evt.action == mouse_release
            m.drag_start = nothing   # avoid stuck drag if mode opened mid-drag
        end
        return
    end

    m.last_event = string(evt.action, " ", evt.button)
    if evt.action == mouse_move || evt.action == mouse_press || evt.action == mouse_drag
        m.hover_x = evt.x
    end

    pa = m.plot_area
    if !contains(pa, evt.x, evt.y)
        if evt.action == mouse_release
            m.drag_start = nothing
        end
        m.hover_x = nothing
        m.hovered = nothing
        return
    end

    n = length(m.data.values)
    if n <= 0
        return
    end

    if evt.button == mouse_scroll_up || evt.button == mouse_scroll_down
        factor = (evt.button == mouse_scroll_up) ? 0.75 : 1.33
        cx = cell_to_data_index(evt.x, pa, m.viewport)
        zoom_viewport_around!(m.viewport, cx, factor, n)
        return
    end

    if evt.action == mouse_press && evt.button == mouse_left
        m.drag_start = (x = evt.x, y = evt.y, vp = deepcopy(m.viewport))
        m.hovered = compute_hovered_index(evt.x, evt.y, pa, m.data, m.viewport)
        m.selected = nothing
        return
    end

    if evt.action == mouse_drag && m.drag_start !== nothing && evt.button == mouse_left
        dx = evt.x - m.drag_start.x
        pan_viewport!(m.viewport, -dx, pa.width, n)
        m.drag_start = (x = evt.x, y = evt.y, vp = deepcopy(m.viewport))
        return
    end

    if evt.action == mouse_release
        m.drag_start = nothing
        m.selected = nearest_point_index_to_cell_x(evt.x, pa, m.viewport, m.data)
        if m.selected !== nothing
            m.hovered = m.selected
        end
        m.hover_x = nothing
        return
    end

    if evt.action == mouse_move
        m.hovered = compute_hovered_index(evt.x, evt.y, pa, m.data, m.viewport)
    end
    _sync_active_back!(m)
end

# ── Dual secondary canvas helpers (KD-P2-15 / 16 / 17) ─────────────────

"""True when visual pref is on and context has a non-empty secondary series."""
function _dual_secondary_eligible(m::SPCWorkbenchModel, ctx::ChartRenderContext)::Bool
    _pref_on(m, "secondary_canvas") || return false
    isempty(ctx.secondary.values) && return false
    return true
end

"""
Split `active` into stacked primary (~62%) + secondary (~35%) outer rects.
Returns `nothing` when outer height cannot host both min sizes (primary ≥8, secondary ≥6).
"""
function _split_dual_plot_rects(active::Rect)
    H = active.height
    H < DUAL_MIN_OUTER_H && return nothing
    h_pri = max(8, round(Int, H * DUAL_PRIMARY_FRAC))
    h_sec = H - h_pri
    if h_sec < 6
        h_pri = H - 6
        h_sec = 6
    end
    (h_pri < 8 || h_sec < 6) && return nothing
    pri = Rect(active.x, active.y, active.width, h_pri)
    sec = Rect(active.x, active.y + h_pri, active.width, h_sec)
    return (pri, sec)
end

"""
Ephemeral secondary Viewport (KD-P2-16). Never store on the model; never mutate `m.viewport`.
Owns X domain only (1..n_sec). Y fit is owned solely by `_render_series_canvas!` (cl/ucl/lcl
extras when `draw_sigma_zones=false`) so fit policy lives in one place.
I-MR: values are length n−1 MRs; index i pairs with primary point i+1 for correlation.
"""
function _ephemeral_secondary_viewport(sec::SecondarySeries)::Viewport
    n = length(sec.values)
    vp = Viewport(x0 = 1, x1 = max(1, n), ylo = 0.0, yhi = 1.0)
    n > 0 && clamp_viewport!(vp, n)
    return vp
end

"""Compact number for axis ticks / line tags (1 decimal — matches HTML-ish TUI density)."""
function _fmt_axis(v::Real)::String
    string(round(Float64(v); digits = 1))
end

"""Right-align `text` on the plot row corresponding to `val` (HTML limit-line tags)."""
function _draw_hline_label!(buf, plot_inner::Rect, viewport::Viewport, val, text::AbstractString, sty)
    isempty(text) && return
    tw = length(text)
    tw > plot_inner.width && return
    yy = data_val_to_cell_row(Float64(val), plot_inner, viewport)
    lx = right(plot_inner) - tw + 1
    lx = max(plot_inner.x, lx)
    set_string!(buf, lx, yy, String(text), sty)
end

"""
Y-axis min/mid/max ticks on the left + X-range indices on the bottom row.
Y min sits one row above the X row when height allows so they do not clobber.
"""
function _draw_axis_labels!(buf, plot_inner::Rect, viewport::Viewport)
    chh = plot_inner.height
    (chh <= 0 || plot_inner.width <= 0) && return
    bot = bottom(plot_inner)
    # Y ticks
    set_string!(buf, plot_inner.x, plot_inner.y, _fmt_axis(viewport.yhi), tstyle(:text_dim))
    if chh >= 3
        set_string!(buf, plot_inner.x, bot - 1, _fmt_axis(viewport.ylo), tstyle(:text_dim))
    else
        set_string!(buf, plot_inner.x, bot, _fmt_axis(viewport.ylo), tstyle(:text_dim))
    end
    if chh >= 5
        midv = (Float64(viewport.ylo) + Float64(viewport.yhi)) / 2
        midy = data_val_to_cell_row(midv, plot_inner, viewport)
        set_string!(buf, plot_inner.x, midy, _fmt_axis(midv), tstyle(:text_dim))
    end
    # X-range indices on bottom
    set_string!(buf, plot_inner.x, bot, string(viewport.x0), tstyle(:text_dim))
    x1s = string(viewport.x1)
    set_string!(buf, max(plot_inner.x, right(plot_inner) - length(x1s) + 1), bot, x1s, tstyle(:text_dim))
end

"""
    _render_series_canvas!(buf, outer, m, f; title, values, viewport, …) -> plot_inner

Draw one series into `outer` Rect: Block(title) + Canvas + connectors + limit lines (KD-P2-17).
Does **not** set `m.plot_area` / `m.viewport` unless `bind_mouse=true` (primary only).
Secondary path: CL/UCL/LCL only (`draw_sigma_zones`/`draw_weco_markers`/`draw_specs`/`draw_hover` false).
"""
function _render_series_canvas!(
    buf, outer::Rect, m::SPCWorkbenchModel, f::Frame;
    title::AbstractString,
    values::AbstractVector{<:Real},
    viewport::Viewport,
    cl::Union{Real,Nothing} = nothing,
    ucl::Union{Real,Nothing} = nothing,
    lcl::Union{Real,Nothing} = nothing,
    lz::Union{LimitsAndZones,Nothing} = nothing,
    ctx::Union{ChartRenderContext,Nothing} = nothing,
    chart::Union{ChartSpec,Nothing} = nothing,
    bind_mouse::Bool = false,
    draw_weco_markers::Bool = false,
    draw_specs::Bool = false,
    draw_sigma_zones::Bool = false,
    draw_hover::Bool = false,
    title_style = tstyle(:title),
    border_style = tstyle(:border),
    usl = nothing,
    lsl = nothing,
)::Rect
    plot_block = Block(title = String(title), border_style = border_style, title_style = title_style)
    plot_inner = render(plot_block, outer, buf)
    if bind_mouse
        m.plot_area = plot_inner
    end

    cw = plot_inner.width
    chh = plot_inner.height
    n_plot = length(values)
    if cw <= 0 || chh <= 0 || n_plot <= 0
        return plot_inner
    end

    clamp_viewport!(viewport, n_plot)

    # Y fit: primary uses full lz + specs prefs; secondary uses cl/ucl/lcl extras only
    if draw_sigma_zones && lz !== nothing
        auto_fit_viewport_y!(viewport, values, lz;
            usl = usl, lsl = lsl, show_lines = m.show_chart_lines)
    else
        extras = Float64[]
        cl !== nothing && isfinite(Float64(cl)) && push!(extras, Float64(cl))
        ucl !== nothing && isfinite(Float64(ucl)) && push!(extras, Float64(ucl))
        lcl !== nothing && isfinite(Float64(lcl)) && push!(extras, Float64(lcl))
        fit_viewport_y!(viewport, values; extras = extras)
    end

    viol_set = ctx === nothing ? Set{Int}() : ctx.viol_indices
    c = create_canvas(cw, chh; style = !isempty(viol_set) ? tstyle(:accent) : tstyle(:primary))
    dw, dh = canvas_dot_size(c)

    prev = nothing
    for i in viewport.x0:viewport.x1
        if i < 1 || i > n_plot
            continue
        end
        v = Float64(values[i])
        dx = map_to_dot_x(i, viewport, dw)
        dy = map_to_dot_y(v, viewport, dh)
        set_point!(c, dx, dy)
        if prev !== nothing && _pref_on(m, "braille_series")
            line!(c, prev[1], prev[2], dx, dy)
        end
        prev = (dx, dy)
    end

    # Limit / zone lines on canvas (styles via draw_limit_hline_canvas!)
    if draw_sigma_zones && lz !== nothing
        if _line_on(m, "sigma1")
            st = _line_style(m, "sigma1")
            for z in (lz.ucl1, lz.lcl1)
                draw_limit_hline_canvas!(c, map_to_dot_y(z, viewport, dh), dw, st)
            end
        end
        if _line_on(m, "sigma2")
            st = _line_style(m, "sigma2")
            for z in (lz.ucl2, lz.lcl2)
                draw_limit_hline_canvas!(c, map_to_dot_y(z, viewport, dh), dw, st)
            end
        end
        if _line_on(m, "sigma3")
            st = _line_style(m, "sigma3")
            draw_limit_hline_canvas!(c, map_to_dot_y(lz.ucl, viewport, dh), dw, st)
            draw_limit_hline_canvas!(c, map_to_dot_y(lz.lcl, viewport, dh), dw, st)
        end
        if _line_on(m, "cl")
            draw_limit_hline_canvas!(c, map_to_dot_y(lz.cl, viewport, dh), dw, _line_style(m, "cl"))
        end
        if draw_specs && _line_on(m, "specs")
            st = _line_style(m, "specs")
            if usl !== nothing
                draw_limit_hline_canvas!(c, map_to_dot_y(Float64(usl), viewport, dh), dw, st)
            end
            if lsl !== nothing
                draw_limit_hline_canvas!(c, map_to_dot_y(Float64(lsl), viewport, dh), dw, st)
            end
        end
    else
        # Dual secondary (or simplified): CL / UCL / LCL only when provided — no _line_on
        if ucl !== nothing
            draw_limit_hline_canvas!(c, map_to_dot_y(Float64(ucl), viewport, dh), dw, _line_style(m, "sigma3"))
        end
        if lcl !== nothing
            draw_limit_hline_canvas!(c, map_to_dot_y(Float64(lcl), viewport, dh), dw, _line_style(m, "sigma3"))
        end
        if cl !== nothing
            draw_limit_hline_canvas!(c, map_to_dot_y(Float64(cl), viewport, dh), dw, _line_style(m, "cl"))
        end
    end

    render_canvas(c, plot_inner, f)

    # Colorized limit overlays on buffer cells (styles via draw_limit_hline_buf!)
    if draw_sigma_zones && lz !== nothing
        if draw_specs && _line_on(m, "specs")
            st = _line_style(m, "specs")
            if usl !== nothing; draw_limit_hline_buf!(buf, plot_inner, usl, viewport, st, tstyle(:error, bold = true)); end
            if lsl !== nothing; draw_limit_hline_buf!(buf, plot_inner, lsl, viewport, st, tstyle(:error, bold = true)); end
        end
        if _line_on(m, "sigma3")
            st = _line_style(m, "sigma3")
            draw_limit_hline_buf!(buf, plot_inner, lz.ucl, viewport, st, tstyle(:warning, bold = true))
            draw_limit_hline_buf!(buf, plot_inner, lz.lcl, viewport, st, tstyle(:warning, bold = true))
        end
        if _line_on(m, "sigma2")
            st = _line_style(m, "sigma2")
            draw_limit_hline_buf!(buf, plot_inner, lz.ucl2, viewport, st, tstyle(:secondary))
            draw_limit_hline_buf!(buf, plot_inner, lz.lcl2, viewport, st, tstyle(:secondary))
        end
        if _line_on(m, "sigma1")
            st = _line_style(m, "sigma1")
            draw_limit_hline_buf!(buf, plot_inner, lz.ucl1, viewport, st, tstyle(:text_dim))
            draw_limit_hline_buf!(buf, plot_inner, lz.lcl1, viewport, st, tstyle(:text_dim))
        end
        if _line_on(m, "cl")
            draw_limit_hline_buf!(buf, plot_inner, lz.cl, viewport, _line_style(m, "cl"), tstyle(:accent))
        end
    else
        # Dual secondary buffer overlays — style only; no _line_on
        if ucl !== nothing
            draw_limit_hline_buf!(buf, plot_inner, ucl, viewport, _line_style(m, "sigma3"), tstyle(:warning, bold = true))
        end
        if lcl !== nothing
            draw_limit_hline_buf!(buf, plot_inner, lcl, viewport, _line_style(m, "sigma3"), tstyle(:warning, bold = true))
        end
        if cl !== nothing
            draw_limit_hline_buf!(buf, plot_inner, cl, viewport, _line_style(m, "cl"), tstyle(:accent))
        end
    end

    # Hover / select overlays (primary only)
    if draw_hover
        if m.hover_x !== nothing
            hx = clamp(m.hover_x, plot_inner.x, right(plot_inner))
            for y in (plot_inner.y + 1):(bottom(plot_inner) - 1)
                set_char!(buf, hx, y, '│', tstyle(:accent))
            end
        end
        if (si = m.selected) !== nothing && 1 <= si <= n_plot && si >= viewport.x0 && si <= viewport.x1
            hx = data_index_to_cell(si, plot_inner, viewport)
            for y in (plot_inner.y + 1):(bottom(plot_inner) - 1)
                set_char!(buf, hx, y, '┃', tstyle(:secondary, bold = true))
            end
        end
        if (hi = m.hovered) !== nothing && 1 <= hi <= n_plot && hi >= viewport.x0 && hi <= viewport.x1
            hy = data_val_to_cell_row(Float64(values[hi]), plot_inner, viewport)
            set_char!(buf, plot_inner.x + 1, hy, '─', tstyle(:accent))
        end
    end

    draw_series_connectors!(buf, plot_inner, values, viewport, m)

    # Y/X ticks after connectors (solid stroke would wipe digits) but before markers
    # so a left-edge OOC ◆ is not replaced by a Y tick digit.
    _draw_axis_labels!(buf, plot_inner, viewport)

    # Point markers
    for i in viewport.x0:viewport.x1
        if i < 1 || i > n_plot
            continue
        end
        dx = data_index_to_cell(i, plot_inner, viewport)
        dy = data_val_to_cell_row(Float64(values[i]), plot_inner, viewport)
        if draw_weco_markers && ctx !== nothing && chart !== nothing
            st = point_status(i, ctx, chart)
            if st == :oos
                sym = '✕'; sty = tstyle(:error, bold = true)
            elseif st == :ooc
                sym = '◆'; sty = tstyle(:warning, bold = true)
            else
                sym = '●'; sty = tstyle(:primary, bold = true)
            end
        else
            sym = '●'; sty = tstyle(:primary, bold = true)
        end
        set_char!(buf, dx, dy, sym, sty)
    end

    # Limit-line tags AFTER markers: last sample often sits on the right edge at CL y
    # and would otherwise erase "CL"/"USL"/…. Right-edge tags win over a single point.
    if draw_sigma_zones && lz !== nothing
        if draw_specs && _line_on(m, "specs")
            if usl !== nothing
                _draw_hline_label!(buf, plot_inner, viewport, usl, "USL", tstyle(:error, bold = true))
            end
            if lsl !== nothing
                _draw_hline_label!(buf, plot_inner, viewport, lsl, "LSL", tstyle(:error, bold = true))
            end
        end
        if _line_on(m, "sigma3")
            _draw_hline_label!(buf, plot_inner, viewport, lz.ucl, "UCL", tstyle(:warning, bold = true))
            _draw_hline_label!(buf, plot_inner, viewport, lz.lcl, "LCL", tstyle(:warning, bold = true))
        end
        if _line_on(m, "cl")
            _draw_hline_label!(buf, plot_inner, viewport, lz.cl, "CL", tstyle(:accent, bold = true))
        end
    else
        if ucl !== nothing
            _draw_hline_label!(buf, plot_inner, viewport, ucl, "UCL", tstyle(:warning, bold = true))
        end
        if lcl !== nothing
            _draw_hline_label!(buf, plot_inner, viewport, lcl, "LCL", tstyle(:warning, bold = true))
        end
        if cl !== nothing
            _draw_hline_label!(buf, plot_inner, viewport, cl, "CL", tstyle(:accent, bold = true))
        end
    end

    if draw_hover && ctx !== nothing
        if (hi = m.hovered) !== nothing && 1 <= hi <= n_plot && hi >= viewport.x0 && hi <= viewport.x1 && m.drag_start === nothing
            draw_hover_tooltip!(buf, plot_inner, hi, Float64(values[hi]), hi in viol_set, viewport;
                usl = usl, target = m.target, lsl = lsl)
        end
    end

    return plot_inner
end

# ── Bottom chrome: Message center (left) + Keys panel (right) ───────────

"""Severity for Message panel coloring: :error | :warning | :success | :accent | :info."""
function _message_severity(m::SPCWorkbenchModel)::Symbol
    m.editing !== nothing && return :accent
    msg = lowercase(m.last_event)
    isempty(msg) && return :info
    if occursin("invalid", msg) || occursin("error", msg) || occursin("fail", msg) ||
       occursin("delete?", msg) || occursin("confirm delete", msg)
        return :error
    end
    if occursin("no charts match", msg) || occursin("warn", msg) ||
       occursin("empty", msg) || occursin("nothing to", msg) || occursin("no tools", msg)
        return :warning
    end
    if occursin("cleared", msg) || occursin("saved", msg) || occursin("imported", msg) ||
       occursin("materialized", msg) || msg == "live on" || occursin("success", msg)
        return :success
    end
    return :info
end

function _message_style(sev::Symbol)
    sev == :error && return tstyle(:error, bold=true)
    sev == :warning && return tstyle(:warning, bold=true)
    sev == :success && return tstyle(:success, bold=true)
    sev == :accent && return tstyle(:accent, bold=true)
    return tstyle(:text)
end

# Key-hint rows: (:section, title) | (:binds, Vector{Tuple{key,label}}) | (:note, text)
# Pretty render: accent keys + " · " separators + ▸ section headers (shared UI language).

"""Dashboard Keys panel structure. Compact = most-used; expanded = full contextual list."""
function _contextual_key_entries(m::SPCWorkbenchModel; expanded::Bool)
    if !expanded
        return [
            (:binds, [("p", "pause"), ("g", "live"), ("m", "lib"), ("x", "tools")]),
            (:binds, [("d", "table"), ("q", "quit"), ("?", "more"), ("h", "help")]),
        ]
    end
    return [
        (:section, "PAGES"),
        (:binds, [("m", "library"), ("x", "tools"), ("d", "table"), ("b", "builder")]),
        (:binds, [("e", "presets"), ("f", "filter"), ("F", "clear"), ("h", "help")]),
        (:binds, [("k", "keymap"), ("?", "less"), ("q", "quit")]),
        (:section, "NAV / LIVE"),
        (:binds, [("[ ]", "chart"), ("p", "pause"), ("g", "live"), ("←→", "pan")]),
        (:binds, [("r/z", "reset"), ("wheel", "zoom"), ("drag", "pan")]),
        (:section, "SPECS / WECO / CONFIG"),
        (:binds, [("u", "USL"), ("t", "Target"), ("l", "LSL"), ("s", "clear")]),
        (:binds, [("1-8", "WECO"), ("c", "config"), ("v", "lines"), ("o", "visual")]),
        (:section, "MOUSE"),
        (:note, "hover tooltip · click select · drag pan"),
    ]
end

"""Per-mode Keys menu entries (library / tools / table / builder / help / keymap)."""
function _mode_key_entries(mode::Symbol; compact::Bool = true)
    if mode === :library
        compact && return [
            (:binds, [("↑↓", "select"), ("↵", "activate"), ("a", "add"), ("c", "clone")]),
            (:binds, [("n", "rename"), ("d", "delete"), ("i", "import"), ("e", "export")]),
            (:binds, [("w", "save"), ("W", "load"), ("f", "filter"), ("Esc", "close")]),
        ]
        return [
            (:section, "NAV"),
            (:binds, [("↑↓", "select"), ("↵", "activate"), ("click", "select"), ("2×", "activate")]),
            (:section, "EDIT"),
            (:binds, [("a", "add"), ("c", "clone"), ("n", "rename"), ("d", "delete")]),
            (:section, "I/O · FILTER"),
            (:binds, [("i", "import"), ("e", "export"), ("w", "save"), ("W", "load")]),
            (:binds, [("f", "filter"), ("F", "clear"), ("Esc", "close"), ("q", "close")]),
        ]
    elseif mode === :tools
        compact && return [
            (:binds, [("↑↓", "select"), ("↵", "filter"), ("a", "add"), ("n", "edit")]),
            (:binds, [("d", "delete"), ("Esc", "close"), ("q", "close")]),
        ]
        return [
            (:section, "TOOLS REGISTRY"),
            (:binds, [("↑↓", "select"), ("↵", "filter+go"), ("a", "add"), ("n", "edit desc")]),
            (:binds, [("d", "delete"), ("Esc", "close"), ("q", "close")]),
            (:note, "registry ≠ chart tools — assign via builder"),
        ]
    elseif mode === :config
        compact && return [
            (:binds, [("↑↓", "select"), ("↵/sp", "toggle"), ("Tab", "section"), ("←→", "style")]),
            (:binds, [("c/v/o", "jump"), ("e", "presets"), ("Esc", "close"), ("q", "close")]),
        ]
        return [
            (:section, "CONFIG"),
            (:binds, [("↑↓", "select"), ("↵/Space", "toggle"), ("1-N", "jump+toggle"), ("←/→", "style (lines)")]),
            (:binds, [("Tab", "cycle section"), ("c", "rules"), ("v", "lines"), ("o", "visual")]),
            (:binds, [("e", "presets menu"), ("s", "presets menu"), ("Esc", "close"), ("q", "close")]),
            (:note, "toggles apply immediately · Esc/q only closes"),
        ]
    elseif mode === :presets
        compact && return [
            (:binds, [("↑↓", "select"), ("↵", "load"), ("l", "load"), ("s", "save")]),
            (:binds, [("d", "delete"), ("Esc", "close"), ("q", "close")]),
        ]
        return [
            (:section, "GRAPH PRESETS"),
            (:binds, [("↑↓", "select"), ("↵/l", "load selected"), ("s", "save current")]),
            (:binds, [("d", "delete"), ("Esc", "close"), ("q", "close")]),
            (:note, "whole set: lines · styles · visual · WECO rules"),
        ]
    elseif mode === :table
        compact && return [
            (:binds, [("←→↑↓", "move"), ("Pg", "page"), ("↵", "edit"), ("r", "materialize")]),
            (:binds, [("Esc", "close"), ("q", "close")]),
        ]
        return [
            (:section, "SHARED TABLE"),
            (:binds, [("←→↑↓", "cell"), ("PgUp/Dn", "page"), ("↵", "edit"), ("r", "rematerialize")]),
            (:binds, [("Esc", "close"), ("q", "close")]),
            (:note, "edits are table-only until r / builder apply"),
        ]
    elseif mode === :builder
        compact && return [
            (:binds, [("↑↓", "field"), ("↵", "edit"), ("a", "apply"), ("1-8", "WECO")]),
            (:binds, [("y", "type"), ("Esc", "close"), ("q", "close")]),
        ]
        return [
            (:section, "BUILDER"),
            (:binds, [("↑↓", "field"), ("↵", "edit/toggle"), ("a", "apply"), ("y", "chart type")]),
            (:binds, [("1-8", "WECO"), ("Esc", "close"), ("q", "close")]),
            (:note, "apply materializes series from table mapping"),
        ]
    elseif mode === :help
        return [
            (:section, "PAGES"),
            (:binds, [("m", "library"), ("x", "tools"), ("d", "table"), ("b", "builder")]),
            (:binds, [("h", "this help"), ("k", "keymap"), ("Esc", "close"), ("q", "close")]),
            (:section, "DASHBOARD"),
            (:binds, [("p", "pause"), ("g", "live"), ("[ ]", "chart"), ("←→", "pan")]),
            (:binds, [("r/z", "reset"), ("u/t/l", "specs"), ("1-8", "WECO"), ("c/v/o", "config")]),
            (:section, "VISUALS"),
            (:note, "◆ OOC (yellow) · ✕ OOS (red) · Cpk band colors · dashed σ zones"),
            (:section, "LIBRARY · TABLE · TOOLS"),
            (:note, "library: a/c/n/d · i/e/w/W I/O · f/F filters"),
            (:note, "table: arrows · Enter edit · r rematerialize (never auto)"),
            (:note, "tools: master ids; assign on charts via builder"),
        ]
    elseif mode === :keymap
        return [
            (:section, "KEYS"),
            (:binds, [("m", "library"), ("x", "tools"), ("d", "table"), ("b", "builder")]),
            (:binds, [("p", "pause"), ("g", "live"), ("f/F", "filter"), ("c/v/o", "config")]),
            (:binds, [("u/t/l", "specs"), ("1-8", "WECO"), ("h", "help"), ("k", "keymap")]),
            (:binds, [("[ ]", "chart"), ("←→", "pan"), ("r/z", "reset"), ("q/Esc", "quit/close")]),
            (:section, "MOUSE"),
            (:binds, [("move", "hover"), ("drag", "pan"), ("click", "select"), ("wheel", "zoom")]),
            (:note, "library: click select · double-click activate"),
        ]
    else
        return [(:note, "no keys for mode")]
    end
end

function _mode_keys_title(mode::Symbol)::String
    mode === :library && return "Keys  · Library"
    mode === :tools && return "Keys  · Tools"
    mode === :config && return "Keys  · Config"
    mode === :presets && return "Keys  · Presets"
    mode === :table && return "Keys  · Table"
    mode === :builder && return "Keys  · Builder"
    mode === :help && return "Keys  · Help"
    mode === :keymap && return "Keys  · Map"
    return "Keys"
end

"""Pack binds into N-up columns; returns (rows, col_w)."""
function _pack_bind_rows(pairs, maxw::Int; cols::Int = 2)
    col_w = max(10, maxw ÷ max(1, cols))
    rows = Vector{Vector{Tuple{String,String}}}()
    row = Tuple{String,String}[]
    for p in pairs
        push!(row, p)
        if length(row) >= cols
            push!(rows, row)
            row = Tuple{String,String}[]
        end
    end
    !isempty(row) && push!(rows, row)
    return rows, col_w
end

function _count_key_entry_rows(entries; grid::Bool = true, cols::Int = 2)::Int
    n = 0
    for e in entries
        if e[1] === :binds && grid
            n += cld(length(e[2]), cols)
        else
            n += 1
        end
    end
    return n
end

function _key_entry_row_count(m::SPCWorkbenchModel; expanded::Bool)::Int
    return _count_key_entry_rows(_contextual_key_entries(m; expanded=expanded); grid=expanded, cols=2)
end

function _gauge_row_height(m::SPCWorkbenchModel, area_h::Int)::Int
    if m.keys_panel_expanded
        nlines = _key_entry_row_count(m; expanded=true)
        want = nlines + 2
        max_ok = max(3, area_h - 1 - 6)
        return clamp(want, 8, max_ok)
    end
    m.editing !== nothing && return min(5, max(4, area_h ÷ 6))
    return 4
end

function _clear_rect!(buf, rect)
    for yy in rect.y:bottom(rect)
        for xx in rect.x:right(rect)
            set_char!(buf, xx, yy, ' ', tstyle(:text))
        end
    end
end

"""
Split full-page mode area into content + bottom Message|Keys chrome.
Returns (content, chrome) or (area, nothing) when too short.
"""
function _split_mode_chrome(area; chrome_h::Int = 0)
    if area.height < 12
        return area, nothing
    end
    h = chrome_h > 0 ? chrome_h : clamp(area.height ÷ 5, 5, 7)
    h = min(h, area.height - 6)
    h < 4 && return area, nothing
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(h)]), area)
    length(rows) < 2 && return area, nothing
    return rows[1], rows[2]
end

"""Draw pretty key entries into an already-opened content rect (inner of a Block)."""
function _render_key_entries_into!(buf, x0::Int, y::Int, bot::Int, max_x::Int, entries;
                                   grid::Bool = true, cols::Int = 2)
    maxw = max(1, max_x - x0 + 1)
    for entry in entries
        y > bot && break
        kind = entry[1]
        if kind === :section
            set_string!(buf, x0, y, _side_trunc(string("▸ ", entry[2]), maxw), tstyle(:accent, bold=true))
            y += 1
        elseif kind === :note
            set_string!(buf, x0, y, _side_trunc(string(entry[2]), maxw), tstyle(:text_dim))
            y += 1
        elseif kind === :binds
            pairs = entry[2]
            if grid
                brows, col_w = _pack_bind_rows(pairs, maxw; cols=cols)
                for brow in brows
                    y > bot && break
                    for (i, (k, lab)) in enumerate(brow)
                        col_x = x0 + (i - 1) * col_w
                        col_x > max_x && break
                        cx = col_x
                        set_string!(buf, cx, y, string(k), tstyle(:accent, bold=true))
                        cx += length(k)
                        if cx + 3 <= max_x
                            set_string!(buf, cx, y, " · ", tstyle(:text_dim))
                            cx += 3
                        end
                        room = min(max_x - cx + 1, col_w - length(k) - 3)
                        if room > 0
                            set_string!(buf, cx, y, _side_trunc(lab, room), tstyle(:text))
                        end
                    end
                    y += 1
                end
            else
                cx = x0
                for (k, lab) in pairs
                    cell_len = length(k) + 3 + length(lab)
                    gap = cx > x0 ? 2 : 0
                    if cx + gap + cell_len - 1 > max_x
                        y += 1
                        y > bot && break
                        cx = x0
                        gap = 0
                    end
                    if gap > 0
                        set_string!(buf, cx, y, "  ", tstyle(:text_dim))
                        cx += 2
                    end
                    set_string!(buf, cx, y, string(k), tstyle(:accent, bold=true))
                    cx += length(k)
                    if cx + 3 <= max_x
                        set_string!(buf, cx, y, " · ", tstyle(:text_dim))
                        cx += 3
                    end
                    room = max_x - cx + 1
                    if room > 0
                        lab_s = _side_trunc(lab, room)
                        set_string!(buf, cx, y, lab_s, tstyle(:text))
                        cx += length(lab_s)
                    end
                end
                y += 1
            end
        end
    end
    return y
end

"""Bordered Keys box (shared style for dashboard + every mode page)."""
function _render_keys_box!(buf, rect; title::AbstractString, entries, grid::Bool = true, cols::Int = 2)
    _clear_rect!(buf, rect)
    inner = render(Block(title=String(title), border_style=tstyle(:border),
                         title_style=tstyle(:accent, bold=true)), rect, buf)
    inner.width < 4 && return
    max_x = inner.x + max(1, inner.width - 1) - 1
    _render_key_entries_into!(buf, inner.x, inner.y, bottom(inner), max_x, entries;
                              grid=grid, cols=cols)
end

function _render_message_panel!(buf, rect, m::SPCWorkbenchModel)
    _clear_rect!(buf, rect)
    title = "Message"
    g1i = render(Block(title=title, border_style=tstyle(:border), title_style=tstyle(:text_dim)), rect, buf)
    g1i.width < 4 && return
    y = g1i.y
    bot = bottom(g1i)
    maxw = max(1, g1i.width - 1)

    # Priority: pending delete → prompt → field edits → last_event
    if m.pending_delete
        msg = isempty(m.last_event) ? "confirm delete? y/N" : m.last_event
        set_string!(buf, g1i.x, y, _side_trunc(msg, maxw), tstyle(:error, bold=true))
        y += 1
        if y <= bot
            set_string!(buf, g1i.x, y, _side_trunc("y confirm · any other cancel", maxw), tstyle(:text_dim))
        end
    elseif m.prompt_kind !== nothing
        kind = string(m.prompt_kind)
        set_string!(buf, g1i.x, y,
            _side_trunc("PROMPT [$kind]: $(m.prompt_buf)_", maxw), tstyle(:accent, bold=true))
        y += 1
        if y <= bot
            set_string!(buf, g1i.x, y,
                _side_trunc("Enter apply · Esc cancel · q types", maxw), tstyle(:text_dim))
        end
    elseif m.editing !== nothing
        field = uppercase(string(m.editing))
        set_string!(buf, g1i.x, y,
            _side_trunc("EDITING $field [$(m.edit_buf)]_", maxw), tstyle(:accent, bold=true))
        y += 1
        if y <= bot
            set_string!(buf, g1i.x, y,
                _side_trunc("Enter apply · Esc cancel · q quit", maxw), tstyle(:text_dim))
        end
    elseif m.table_editing
        set_string!(buf, g1i.x, y,
            _side_trunc("EDIT cell r=$(m.table_row) c=$(m.table_col) [$(m.table_buf)]_", maxw),
            tstyle(:accent, bold=true))
        y += 1
        if y <= bot
            set_string!(buf, g1i.x, y,
                _side_trunc("Enter commit · Esc cancel", maxw), tstyle(:text_dim))
        end
    elseif m.builder_editing
        set_string!(buf, g1i.x, y,
            _side_trunc("EDIT field [$(m.builder_buf)]_", maxw), tstyle(:accent, bold=true))
        y += 1
        if y <= bot
            set_string!(buf, g1i.x, y,
                _side_trunc("Enter set · Esc cancel", maxw), tstyle(:text_dim))
        end
    else
        sev = _message_severity(m)
        sty = _message_style(sev)
        msg = isempty(m.last_event) ? "(ready)" : m.last_event
        set_string!(buf, g1i.x, y, _side_trunc(msg, maxw), sty)
    end
end

function _render_keys_panel!(buf, rect, m::SPCWorkbenchModel)
    title = m.keys_panel_expanded ? "Keys  (? collapse)" : "Keys  (? expand)"
    entries = _contextual_key_entries(m; expanded=m.keys_panel_expanded)
    grid = m.keys_panel_expanded
    _render_keys_box!(buf, rect; title=title, entries=entries, grid=grid, cols=2)
end

"""Bottom Message|Keys chrome shared by library/tools/table/builder overlays."""
function _render_mode_chrome!(buf, chrome, m::SPCWorkbenchModel; mode::Symbol)
    gcols = split_layout(Layout(Horizontal, [Fill(), Fill()]), chrome)
    length(gcols) < 2 && return
    _render_message_panel!(buf, gcols[1], m)
    # 2-up chip grid when chrome has room; otherwise pack left→right
    grid = chrome.height >= 5
    entries = _mode_key_entries(mode; compact=true)
    _render_keys_box!(buf, gcols[2]; title=_mode_keys_title(mode), entries=entries,
                      grid=grid, cols=2)
end

"""Full-page styled help/keymap: title strip + Keys-style body (no dual chrome)."""
function _render_styled_doc_page!(buf, area, m; title::AbstractString, mode::Symbol)
    _clear_rect!(buf, area)
    set_string!(buf, area.x + 1, area.y, String(title), tstyle(:title, bold=true))
    # Body in a bordered Keys-like panel under the title
    body = Rect(area.x, area.y + 1, area.width, max(3, area.height - 1))
    entries = _mode_key_entries(mode; compact=false)
    # Message strip on the left when wide enough; else full keys doc
    if area.width >= 60
        cols = split_layout(Layout(Horizontal, [Fixed(max(22, area.width ÷ 3)), Fill()]), body)
        if length(cols) >= 2
            _render_message_panel!(buf, cols[1], m)
            _render_keys_box!(buf, cols[2]; title=_mode_keys_title(mode), entries=entries,
                              grid=true, cols=2)
            return
        end
    end
    _render_keys_box!(buf, body; title=_mode_keys_title(mode), entries=entries, grid=true, cols=2)
end

# ── View (full, with slices) ────────────────────────────────────────────

function view(m::SPCWorkbenchModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    _ensure_charts!(m)
    ch = current_chart(m)
    n = length(m.data.values)

    # live (slice 6 / PR3) — on active; shared gate with advance_live!
    if _live_may_advance(m) && (m.tick % 4 == 0)
        advance_live!(m)
        if n > 0 && m.viewport.x1 >= n - 1
            m.viewport.x1 = n
            if m.viewport.x1 - m.viewport.x0 > 80
                m.viewport.x0 = max(1, m.viewport.x1 - 60)
            end
            clamp_viewport!(m.viewport, n)
        end
        _sync_active_back!(m)
    end

    if area.width < 20 || area.height < 6
        set_string!(buf, area.x, area.y,
            m.view_mode === :config ? "config open [Esc/q]" : "SPC Workbench (small)", tstyle(:text_dim))
        return
    end

    # Mode overlays: help / keymap / library / builder / tools / config / table (dedicated pages; no dashboard bleed)
    if m.view_mode == :help
        _render_help_page!(buf, area, m)
        return
    elseif m.view_mode == :keymap
        _render_keymap_page!(buf, area, m)
        return
    elseif m.view_mode == :library
        _render_library_page!(buf, area, m)
        return
    elseif m.view_mode == :builder
        _render_builder_page!(buf, area, m)
        return
    elseif m.view_mode == :tools
        _render_tools_page!(buf, area, m)
        return
    elseif m.view_mode == :config
        _render_config_page!(buf, area, m)
        return
    elseif m.view_mode == :presets
        _render_presets_page!(buf, area, m)
        return
    elseif m.view_mode == :table
        _render_table_page!(buf, area, m)
        return
    end

    # layout — header + main + bottom panels (no status footer; Message owns events)
    gauge_h = _gauge_row_height(m, area.height)
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(gauge_h)]), area)
    if length(rows) < 3
        return
    end
    header = rows[1]
    main = rows[2]
    gauge_row = rows[3]

    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(28)]), main)
    if length(cols) < 2
        return
    end
    plot_rect = cols[1]
    side_rect = cols[2]

    # Dashboard: up to k panes from active + following visible neighbors (not charts[2]/[3] lock)
    panes = dashboard_pane_charts(m; k = 3)
    npanes = length(panes)
    is_dashboard_multi = (m.view_mode == :dashboard && npanes >= 2)
    active_plot_rect = plot_rect
    second_plot_rect = nothing
    third_plot_rect = nothing
    if is_dashboard_multi
        nc = min(3, npanes)
        if nc == 3
            h1 = max(8, (plot_rect.height * 5) ÷ 10)
            h2 = max(5, (plot_rect.height - h1 - 2) * 5 ÷ 10)
            active_plot_rect = Rect(plot_rect.x, plot_rect.y, plot_rect.width, h1)
            second_plot_rect = Rect(plot_rect.x, plot_rect.y + h1 + 1, plot_rect.width, h2)
            third_plot_rect = Rect(plot_rect.x, plot_rect.y + h1 + 1 + h2 + 1, plot_rect.width, max(3, plot_rect.height - h1 - h2 - 2))
        else
            h1 = max(6, (plot_rect.height * 6) ÷ 10)
            active_plot_rect = Rect(plot_rect.x, plot_rect.y, plot_rect.width, h1)
            second_plot_rect = Rect(plot_rect.x, plot_rect.y + h1 + 1, plot_rect.width, max(3, plot_rect.height - h1 - 1))
        end
    end

    # Dual secondary eligibility + temporary single-pane compress (KD-P2-15)
    # Resolve active context once for dual decision (reuse for primary draw below).
    ch_for_dual = current_chart(m)
    dual_ctx = (n > 0 && length(ch_for_dual.data.values) > 0) ?
        resolve_chart_render_context(ch_for_dual; sigma_method = :mr) : nothing
    dual_eligible = dual_ctx !== nothing && _dual_secondary_eligible(m, dual_ctx)
    if dual_eligible && is_dashboard_multi && active_plot_rect.height < DUAL_MIN_OUTER_H
        # Temporary compress only when full plot can actually host dual (else keep multi + primary-only)
        if plot_rect.height >= DUAL_MIN_OUTER_H
            is_dashboard_multi = false
            active_plot_rect = plot_rect
            second_plot_rect = nothing
            third_plot_rect = nothing
        end
    end
    dual_split = dual_eligible ? _split_dual_plot_rects(active_plot_rect) : nothing
    show_dual = dual_split !== nothing

    # header — short title only; key bindings live in bottom Keys panel
    nch_hdr = length(m.charts)
    hdr = "SPC Workbench [dashboard]  chart $(m.active)/$(max(1, nch_hdr))"
    set_string!(buf, header.x + 1, header.y, hdr, tstyle(:title, bold=true))

    # A6: empty filter match — plot message + side list (Charts: 0/N) + bottom panels
    if npanes == 0 && _any_filter_active(m)
        set_string!(buf, plot_rect.x + 2, plot_rect.y + max(1, plot_rect.height ÷ 2),
            "No charts match filters", tstyle(:warning, bold=true))
        set_string!(buf, plot_rect.x + 2, plot_rect.y + max(2, plot_rect.height ÷ 2 + 1),
            "Press [f] to edit filters or [F] to clear. Demo tools may be empty.", tstyle(:text_dim))
        m.plot_area = plot_rect
        # Side panel still shows filtered count (design: side list always uses visible_charts)
        side_block = Block(title="Side Stats (chart $(m.active)/$(max(1,length(m.charts))) • dashboard)", border_style=tstyle(:border))
        side_inner = render(side_block, side_rect, buf)
        m.side_area = side_inner
        nch_all = length(m.charts)
        set_string!(buf, side_inner.x, side_inner.y, "Charts: 0/$nch_all", tstyle(:text_dim))
        if side_inner.y + 1 <= bottom(side_inner)
            set_string!(buf, side_inner.x, side_inner.y + 1, " (no match)", tstyle(:warning))
        end
        gcols = split_layout(Layout(Horizontal, [Fill(), Fill()]), gauge_row)
        if length(gcols) >= 2
            _render_message_panel!(buf, gcols[1], m)
            _render_keys_panel!(buf, gcols[2], m)
        end
        return
    end

    # Active primary (+ optional dual secondary canvas under it — KD-P2-15/16/17)
    chname = isempty(m.charts) ? "Data" : current_chart(m).name
    empty_hint = (n == 0) ? " — No data — import CSV or clone a demo" : ""
    pri_title = "Dashboard: $(chname) [$(m.active)/$(length(m.charts))] (│ hover  ┃ select  drag pan  wheel zoom)  [ ] switch$(empty_hint)"
    primary_outer = show_dual ? dual_split[1] : active_plot_rect
    secondary_outer = show_dual ? dual_split[2] : nothing

    ch_act = current_chart(m)
    ctx = dual_ctx === nothing ?
        (n > 0 ? resolve_chart_render_context(ch_act; sigma_method = :mr) : nothing) :
        dual_ctx

    if n > 0 && ctx !== nothing && !isempty(ctx.primary_values)
        plot_vals = ctx.primary_values
        n_plot = length(plot_vals)
        lz_disp = ctx.lz
        # Keep viewport within primary length (Xbar has fewer points than raw series)
        clamp_viewport!(m.viewport, n_plot)
        ch_act.viewport = m.viewport

        _render_series_canvas!(
            buf, primary_outer, m, f;
            title = pri_title,
            values = plot_vals,
            viewport = m.viewport,
            cl = lz_disp.cl, ucl = lz_disp.ucl, lcl = lz_disp.lcl,
            lz = lz_disp,
            ctx = ctx,
            chart = ch_act,
            bind_mouse = true,
            draw_weco_markers = true,
            draw_specs = true,
            draw_sigma_zones = true,
            draw_hover = true,
            usl = m.usl,
            lsl = m.lsl,
        )
        # Primary-only ownership: plot_area set by helper; viewport Y from primary fit only
        ch_act.viewport = m.viewport

        # Dual secondary: ephemeral Viewport; never mutates m.viewport / m.plot_area (KD-P2-16)
        if show_dual && secondary_outer !== nothing
            sec = ctx.secondary
            if !isempty(sec.values)
                sec_vp = _ephemeral_secondary_viewport(sec)
                sec_title = "$(sec.name) (secondary)"
                _render_series_canvas!(
                    buf, secondary_outer, m, f;
                    title = sec_title,
                    values = sec.values,
                    viewport = sec_vp,
                    cl = sec.cl, ucl = sec.ucl, lcl = sec.lcl,
                    bind_mouse = false,
                    draw_weco_markers = false,
                    draw_specs = false,
                    draw_sigma_zones = false,
                    draw_hover = false,
                    title_style = tstyle(:text_dim),
                    border_style = tstyle(:border),
                )
            end
        end
    else
        # Empty / no primary: still draw a Block shell and bind mouse area to primary outer
        plot_block = Block(title = pri_title, border_style = tstyle(:border), title_style = tstyle(:title))
        plot_inner = render(plot_block, primary_outer, buf)
        m.plot_area = plot_inner
    end

    # Read-only extra panes from dashboard_pane_charts (panes[2], panes[3]) — not m.charts[2]/[3]
    if is_dashboard_multi && second_plot_rect !== nothing && npanes >= 2
        ch2 = panes[2]
        n2_raw = length(ch2.data.values)
        if n2_raw > 0 && second_plot_rect.width > 4 && second_plot_rect.height > 3
            blk2 = Block(title = "Chart 2: $(ch2.name) (read-only view)", border_style = tstyle(:border), title_style = tstyle(:text_dim))
            inn2 = render(blk2, second_plot_rect, buf)
            cw2, ch2h = inn2.width, inn2.height
            if cw2 > 0 && ch2h > 0
                ctx2 = resolve_chart_render_context(ch2; sigma_method=:mr)
                viol2 = ctx2.viol_indices
                plot2 = ctx2.primary_values
                n2 = length(plot2)
                if n2 > 0
                    clamp_viewport!(ch2.viewport, n2)
                    auto_fit_viewport_y!(ch2.viewport, plot2, ctx2.lz;
                        usl = ch2.usl, lsl = ch2.lsl, show_lines = m.show_chart_lines)
                end
                c2 = create_canvas(cw2, ch2h; style = !isempty(viol2) ? tstyle(:accent) : tstyle(:primary))
                dw2, dh2 = canvas_dot_size(c2)
                prev2 = nothing
                vp2 = ch2.viewport
                for i in vp2.x0 : vp2.x1
                    (i<1 || i>n2) && continue
                    v = plot2[i]
                    dx = map_to_dot_x(i, vp2, dw2)
                    dy = map_to_dot_y(v, vp2, dh2)
                    set_point!(c2, dx, dy)
                    if prev2 !== nothing && _pref_on(m, "braille_series")
                        line!(c2, prev2[1], prev2[2], dx, dy)
                    end
                    prev2 = (dx, dy)
                end
                lz2 = ctx2.lz
                if _line_on(m, "sigma1")
                    st = _line_style(m, "sigma1")
                    for z in (lz2.ucl1, lz2.lcl1)
                        draw_limit_hline_canvas!(c2, map_to_dot_y(z, vp2, dh2), dw2, st)
                    end
                end
                if _line_on(m, "sigma2")
                    st = _line_style(m, "sigma2")
                    for z in (lz2.ucl2, lz2.lcl2)
                        draw_limit_hline_canvas!(c2, map_to_dot_y(z, vp2, dh2), dw2, st)
                    end
                end
                if _line_on(m, "sigma3")
                    st = _line_style(m, "sigma3")
                    draw_limit_hline_canvas!(c2, map_to_dot_y(lz2.ucl, vp2, dh2), dw2, st)
                    draw_limit_hline_canvas!(c2, map_to_dot_y(lz2.lcl, vp2, dh2), dw2, st)
                end
                if _line_on(m, "cl")
                    draw_limit_hline_canvas!(c2, map_to_dot_y(lz2.cl, vp2, dh2), dw2, _line_style(m, "cl"))
                end
                if _line_on(m, "specs")
                    st = _line_style(m, "specs")
                    if ch2.usl !== nothing
                        draw_limit_hline_canvas!(c2, map_to_dot_y(ch2.usl, vp2, dh2), dw2, st)
                    end
                    if ch2.lsl !== nothing
                        draw_limit_hline_canvas!(c2, map_to_dot_y(ch2.lsl, vp2, dh2), dw2, st)
                    end
                end
                render_canvas(c2, inn2, f)
                # Colorized overlays for ch2 (same as active; gated + style-aware)
                if _line_on(m, "specs")
                    st = _line_style(m, "specs")
                    if ch2.usl !== nothing; draw_limit_hline_buf!(buf, inn2, ch2.usl, vp2, st, tstyle(:error, bold=true)); end
                    if ch2.lsl !== nothing; draw_limit_hline_buf!(buf, inn2, ch2.lsl, vp2, st, tstyle(:error, bold=true)); end
                end
                if _line_on(m, "sigma3")
                    st = _line_style(m, "sigma3")
                    draw_limit_hline_buf!(buf, inn2, lz2.ucl, vp2, st, tstyle(:warning, bold=true))
                    draw_limit_hline_buf!(buf, inn2, lz2.lcl, vp2, st, tstyle(:warning, bold=true))
                end
                if _line_on(m, "sigma2")
                    st = _line_style(m, "sigma2")
                    draw_limit_hline_buf!(buf, inn2, lz2.ucl2, vp2, st, tstyle(:secondary))
                    draw_limit_hline_buf!(buf, inn2, lz2.lcl2, vp2, st, tstyle(:secondary))
                end
                if _line_on(m, "sigma1")
                    st = _line_style(m, "sigma1")
                    draw_limit_hline_buf!(buf, inn2, lz2.ucl1, vp2, st, tstyle(:text_dim))
                    draw_limit_hline_buf!(buf, inn2, lz2.lcl1, vp2, st, tstyle(:text_dim))
                end
                if _line_on(m, "cl")
                    draw_limit_hline_buf!(buf, inn2, lz2.cl, vp2, _line_style(m, "cl"), tstyle(:accent))
                end
                draw_series_connectors!(buf, inn2, plot2, vp2, m)
                # markers for ch2 (OOC/OOS) on primary series
                for i in vp2.x0:vp2.x1
                    (i<1||i>n2) && continue
                    dx = data_index_to_cell(i, inn2, vp2)
                    dy = data_val_to_cell_row(plot2[i], inn2, vp2)
                    st2 = point_status(i, ctx2, ch2)
                    if st2 == :oos
                        sym2 = '✕'; sty2 = tstyle(:error, bold=true)
                    elseif st2 == :ooc
                        sym2 = '◆'; sty2 = tstyle(:warning, bold=true)  # yellow WECO / OOC diamond
                    else
                        sym2 = '●'; sty2 = tstyle(:primary, bold=true)
                    end
                    set_char!(buf, dx, dy, sym2, sty2)
                end
            end
        end
    end

    # THIRD pane when panes has a third neighbor
    if third_plot_rect !== nothing && npanes >= 3
        ch3 = panes[3]
        n3_raw = length(ch3.data.values)
        if n3_raw > 0 && third_plot_rect.width > 4 && third_plot_rect.height > 3
            blk3 = Block(title = "Chart 3: $(ch3.name) (read-only)", border_style = tstyle(:border), title_style = tstyle(:text_dim))
            inn3 = render(blk3, third_plot_rect, buf)
            cw3, ch3h = inn3.width, inn3.height
            if cw3 > 0 && ch3h > 0
                ctx3 = resolve_chart_render_context(ch3; sigma_method=:mr)
                viol3 = ctx3.viol_indices
                plot3 = ctx3.primary_values
                n3 = length(plot3)
                if n3 > 0
                    clamp_viewport!(ch3.viewport, n3)
                    auto_fit_viewport_y!(ch3.viewport, plot3, ctx3.lz;
                        usl = ch3.usl, lsl = ch3.lsl, show_lines = m.show_chart_lines)
                end
                c3 = create_canvas(cw3, ch3h; style = !isempty(viol3) ? tstyle(:accent) : tstyle(:primary))
                dw3, dh3 = canvas_dot_size(c3)
                prev3 = nothing
                vp3 = ch3.viewport
                for i in vp3.x0:vp3.x1
                    (i<1 || i>n3) && continue
                    v = plot3[i]
                    dx = map_to_dot_x(i, vp3, dw3)
                    dy = map_to_dot_y(v, vp3, dh3)
                    set_point!(c3, dx, dy)
                    if prev3 !== nothing && _pref_on(m, "braille_series")
                        line!(c3, prev3[1], prev3[2], dx, dy)
                    end
                    prev3 = (dx, dy)
                end
                lz3 = ctx3.lz
                if _line_on(m, "sigma1")
                    st = _line_style(m, "sigma1")
                    for z in (lz3.ucl1, lz3.lcl1)
                        draw_limit_hline_canvas!(c3, map_to_dot_y(z, vp3, dh3), dw3, st)
                    end
                end
                if _line_on(m, "sigma2")
                    st = _line_style(m, "sigma2")
                    for z in (lz3.ucl2, lz3.lcl2)
                        draw_limit_hline_canvas!(c3, map_to_dot_y(z, vp3, dh3), dw3, st)
                    end
                end
                if _line_on(m, "sigma3")
                    st = _line_style(m, "sigma3")
                    draw_limit_hline_canvas!(c3, map_to_dot_y(lz3.ucl, vp3, dh3), dw3, st)
                    draw_limit_hline_canvas!(c3, map_to_dot_y(lz3.lcl, vp3, dh3), dw3, st)
                end
                if _line_on(m, "cl")
                    draw_limit_hline_canvas!(c3, map_to_dot_y(lz3.cl, vp3, dh3), dw3, _line_style(m, "cl"))
                end
                if _line_on(m, "specs")
                    st = _line_style(m, "specs")
                    if ch3.usl !== nothing
                        draw_limit_hline_canvas!(c3, map_to_dot_y(ch3.usl, vp3, dh3), dw3, st)
                    end
                    if ch3.lsl !== nothing
                        draw_limit_hline_canvas!(c3, map_to_dot_y(ch3.lsl, vp3, dh3), dw3, st)
                    end
                end
                render_canvas(c3, inn3, f)
                # color overlays + markers for ch3 (gated + style-aware)
                if _line_on(m, "specs")
                    st = _line_style(m, "specs")
                    if ch3.usl !== nothing; draw_limit_hline_buf!(buf, inn3, ch3.usl, vp3, st, tstyle(:error, bold=true)); end
                    if ch3.lsl !== nothing; draw_limit_hline_buf!(buf, inn3, ch3.lsl, vp3, st, tstyle(:error, bold=true)); end
                end
                if _line_on(m, "sigma3")
                    st = _line_style(m, "sigma3")
                    draw_limit_hline_buf!(buf, inn3, lz3.ucl, vp3, st, tstyle(:warning, bold=true))
                    draw_limit_hline_buf!(buf, inn3, lz3.lcl, vp3, st, tstyle(:warning, bold=true))
                end
                if _line_on(m, "sigma2")
                    st = _line_style(m, "sigma2")
                    draw_limit_hline_buf!(buf, inn3, lz3.ucl2, vp3, st, tstyle(:secondary))
                    draw_limit_hline_buf!(buf, inn3, lz3.lcl2, vp3, st, tstyle(:secondary))
                end
                if _line_on(m, "sigma1")
                    st = _line_style(m, "sigma1")
                    draw_limit_hline_buf!(buf, inn3, lz3.ucl1, vp3, st, tstyle(:text_dim))
                    draw_limit_hline_buf!(buf, inn3, lz3.lcl1, vp3, st, tstyle(:text_dim))
                end
                if _line_on(m, "cl")
                    draw_limit_hline_buf!(buf, inn3, lz3.cl, vp3, _line_style(m, "cl"), tstyle(:accent))
                end
                draw_series_connectors!(buf, inn3, plot3, vp3, m)
                for i in vp3.x0:vp3.x1
                    (i<1||i>n3)&&continue
                    dx=data_index_to_cell(i,inn3,vp3); dy=data_val_to_cell_row(plot3[i],inn3,vp3)
                    st3 = point_status(i, ctx3, ch3)
                    if st3 == :oos
                        sym3 = '✕'; sty3 = tstyle(:error, bold=true)
                    elseif st3 == :ooc
                        sym3 = '◆'; sty3 = tstyle(:warning, bold=true)  # yellow WECO / OOC diamond
                    else
                        sym3 = '●'; sty3 = tstyle(:primary, bold=true)
                    end
                    set_char!(buf, dx, dy, sym3, sty3)
                end
            end
        end
    end

    # side
    side_block = Block(title="Side Stats (chart $(m.active)/$(max(1,length(m.charts))) • dashboard)", border_style=tstyle(:border))
    side_inner = render(side_block, side_rect, buf)
    m.side_area = side_inner
    x = side_inner.x
    y = side_inner.y
    if n > 0
        # Use the resolved ctx for active (canonical limits + band) to avoid duplication
        act_ch = current_chart(m)
        act_ctx = resolve_chart_render_context(act_ch; sigma_method=:mr)
        lz = act_ctx.lz
        n_primary = length(act_ctx.primary_values)
        # Mode badge = effective gateway path (same predicate as resolve_chart_render_context)
        mode_lbl = _manual_limits_effective(act_ch) ? "limits:manual" : "limits:auto"
        set_string!(buf, x, y, "n=$n_primary $mode_lbl", tstyle(:text)); y += 1
        # Secondary stats (Rbar/sbar/MRbar); dual secondary canvas under active plot when pref on
        cl_sigma = "cl=$(round(lz.cl;digits=2)) σ=$(round(lz.sigma;digits=2))"
        if act_ctx.secondary_bar !== nothing && !isempty(act_ctx.secondary_name)
            sec_lbl = if act_ctx.secondary_name == "R"
                "Rbar"
            elseif act_ctx.secondary_name == "s"
                "sbar"
            elseif act_ctx.secondary_name == "MR"
                "MRbar"
            else
                act_ctx.secondary_name
            end
            cl_sigma *= " $sec_lbl=$(round(act_ctx.secondary_bar; digits=2))"
        end
        set_string!(buf, x, y, cl_sigma, tstyle(:text_dim)); y += 1
        cpk_s = act_ctx.cpk === nothing ? "—" : _fmt(act_ctx.cpk)
        band = act_ctx.band
        cpk_st = band == :green ? tstyle(:success, bold=true) : (band == :red ? tstyle(:error, bold=true) : (band == :amber ? tstyle(:warning, bold=true) : tstyle(:text)))
        set_string!(buf, x, y, "Cpk=$cpk_s", cpk_st); y += 1
        if act_ctx.cpk !== nothing
            set_string!(buf, x, y, "band:$(band) $(cpk_color_for_band(band))", tstyle(:text_dim)); y += 1
        end
        if m.usl !== nothing || m.lsl !== nothing
            set_string!(buf, x, y, "USL=$(m.usl===nothing ? "—" : round(m.usl;digits=1)) T=$(m.target===nothing ? "—" : round(m.target;digits=1)) LSL=$(m.lsl===nothing ? "—" : round(m.lsl;digits=1))", tstyle(:text_dim)); y += 1
        end
        # Hover first (priority over long line list when side is short) — primary series index
        if (hi = m.hovered) !== nothing && 1 <= hi <= n_primary
            if y <= bottom(side_inner) - 1
                v = act_ctx.primary_values[hi]
                st = point_status(hi, act_ctx, act_ch)
                stat = st == :oos ? "OOS" : (st == :ooc ? "OOC" : "OK")
                set_string!(buf, x, y, "h[$hi]=$(round(v;digits=2)) $stat", tstyle(:accent, bold=true))
                y += 1
            end
        end
        # Chart line parameters (●/○ = draw on chart; [v] config). Compact: header + 5 value rows.
        if y <= bottom(side_inner) - 1
            set_string!(buf, x, y, "Lines [v]", tstyle(:text_dim)); y += 1
        end
        usl_s = m.usl === nothing ? "—" : string(round(m.usl; digits=1))
        lsl_s = m.lsl === nothing ? "—" : string(round(m.lsl; digits=1))
        line_rows = (
            ("CL", "cl", string(round(lz.cl; digits=2))),
            ("±1σ", "sigma1", "$(round(lz.ucl1; digits=2))/$(round(lz.lcl1; digits=2))"),
            ("±2σ", "sigma2", "$(round(lz.ucl2; digits=2))/$(round(lz.lcl2; digits=2))"),
            ("±3σ", "sigma3", "UCL=$(round(lz.ucl; digits=2)) LCL=$(round(lz.lcl; digits=2))"),
            ("Specs", "specs", "USL=$usl_s LSL=$lsl_s"),
        )
        for (label, key, valstr) in line_rows
            if y > bottom(side_inner) - 1
                break
            end
            on = _line_on(m, key)
            set_char!(buf, x, y, on ? '●' : '○', on ? tstyle(:success) : tstyle(:text_dim))
            set_string!(buf, x + 2, y, "$label=$valstr", tstyle(:text_dim))
            y += 1
        end
        # WECO on/off bubbles: ● green when enabled, ○ dim when off (rules 1–8)
        # Optional blank gap after Specs when there is room for gap + WECO row.
        # Numbers 1–8 under each bubble when a second row fits.
        bot = bottom(side_inner)
        if y + 1 <= bot  # at least one row left for WECO bubbles
            # blank spacer only if Specs→WECO gap and bubble row both fit
            if y + 2 <= bot
                y += 1
            end
            if y <= bot
                set_string!(buf, x, y, "WECO ", tstyle(:text_dim))
                bx0 = x + 5
                bx = bx0
                for i in 1:8
                    rid = "WECO-$i"
                    on = get(act_ch.enabled_rules, rid, false)
                    if bx <= right(side_inner)
                        set_char!(buf, bx, y, on ? '●' : '○', on ? tstyle(:success) : tstyle(:text_dim))
                    end
                    bx += 1
                end
                y += 1
                # digit row under bubbles when space remains
                if y <= bot
                    for i in 1:8
                        nx = bx0 + i - 1
                        if nx <= right(side_inner)
                            set_char!(buf, nx, y, Char('0' + i), tstyle(:text_dim))
                        end
                    end
                    y += 1
                end
            end
        end
        # Last-N WECO msgs by sample index (most recent); chart-scoped data/rules (PR5 / P1.8)
        side_viols = weco_detect(act_ch.data.values, lz.cl, lz.sigma; enabled_rules = act_ch.enabled_rules)
        show_viols = _side_viol_msgs_by_index(side_viols; n = SIDE_VIOL_MSG_MAX)
        nv = length(side_viols)
        if y <= bot
            set_string!(buf, x, y, "Viols: $nv", nv > 0 ? tstyle(:warning) : tstyle(:text_dim))
            y += 1
        end
        if !isempty(show_viols)
            maxw = max(4, side_inner.width - 1)
            for v in show_viols
                y > bot && break
                line = _side_trunc("$(v.rule) $(v.msg)", maxw)
                set_string!(buf, x, y, line, tstyle(:warning))
                y += 1
            end
        end
        # dashboard multi hint (lowest priority when cramped) — filtered list (GC-PR4)
        side_vis = visible_charts(m)
        nch_all = length(m.charts)
        nvis_side = length(side_vis)
        if nch_all > 1 || _any_filter_active(m)
            if y <= bottom(side_inner) - 1
                cnt = _any_filter_active(m) ? "Charts: $nvis_side/$nch_all" : "Charts: $nch_all"
                set_string!(buf, x, y, cnt, tstyle(:text_dim))
                y += 1
            end
            if nvis_side == 0 && _any_filter_active(m)
                if y <= bottom(side_inner) - 1
                    set_string!(buf, x, y, " (no match)", tstyle(:warning))
                    y += 1
                end
            else
                act_id = current_chart(m).id
                for c in side_vis
                    if y > bottom(side_inner) - 1; break; end
                    cctx = resolve_chart_render_context(c; sigma_method=:mr)
                    is_act = c.id == act_id
                    set_string!(buf, x, y, " $(is_act ? "▶" : " ") $(c.name[1:min(8,length(c.name))]) cpk=$(_fmt(cctx.cpk))", tstyle(is_act ? :accent : :text_dim))
                    y += 1
                end
            end
        end
    else
        set_string!(buf, x, y, "n=0", tstyle(:text))
    end

    # Bottom panels: Message center (left) + Keys (right) — no status footer strip
    gcols = split_layout(Layout(Horizontal, [Fill(), Fill()]), gauge_row)
    if length(gcols) >= 2
        _render_message_panel!(buf, gcols[1], m)
        _render_keys_panel!(buf, gcols[2], m)
    end
end

# small helper for fmt
function _fmt(x)
    if x === nothing
        return "—"
    end
    x < 1 ? string(round(x; digits=3)) : string(round(x; digits=2))
end

# Side-panel WECO violation message list (last N by sample index; PR5 / P1.8)
const SIDE_VIOL_MSG_MAX = 5

function _side_trunc(s::AbstractString, maxw::Int)::String
    maxw <= 0 && return ""
    io = IOBuffer()
    n = 0
    for c in s
        n += 1
        n > maxw && break
        print(io, c)
    end
    String(take!(io))
end

"""
    _side_viol_msgs_by_index(viols; n=SIDE_VIOL_MSG_MAX) -> Vector{WECOViolation}

Policy: last-N by **sample index** (most recent points), not rule-number tail of
`weco_detect` order. Stable secondary key is rule name. Returns ascending index
order for display (oldest of the selected window first).
"""
function _side_viol_msgs_by_index(
    viols::AbstractVector{WECOViolation};
    n::Int = SIDE_VIOL_MSG_MAX,
)::Vector{WECOViolation}
    isempty(viols) && return WECOViolation[]
    n <= 0 && return WECOViolation[]
    sorted = sort(collect(viols); by = v -> (v.index, v.rule))
    start = max(1, length(sorted) - n + 1)
    return sorted[start:end]
end

# ── Chart Library page (GC-PR2 / A5) — list uses visible_charts (GC-PR4) ─
function _render_library_page!(buf, area, m)
    content, chrome = _split_mode_chrome(area)
    m.library_area = content
    set_string!(buf, content.x + 1, content.y,
        "CHART LIBRARY  ·  Esc/q → dashboard", tstyle(:title, bold=true))
    y = content.y + 2
    nch = length(m.charts)
    if nch >= 1
        m.library_selected = clamp(m.library_selected, 1, nch)
    end
    vis_charts = visible_charts(m)
    nvis = length(vis_charts)
    filt_bits = String[]
    !isempty(m.filter_tool) && push!(filt_bits, "tool=$(m.filter_tool)")
    !isempty(m.filter_type) && push!(filt_bits, "type=$(m.filter_type)")
    !isempty(m.filter_owner) && push!(filt_bits, "owner=$(m.filter_owner)")
    filt_lbl = isempty(filt_bits) ? "none" : join(filt_bits, " ")
    set_string!(buf, content.x + 2, y,
        "Charts: $nvis/$nch   active=$(m.active)   selected=$(m.library_selected)   filters: $filt_lbl",
        tstyle(:text_dim))
    y += 2
    list_bottom = bottom(content)
    capacity = max(1, list_bottom - y + 1)
    _sync_library_scroll_vis!(m, vis_charts, capacity)
    if nvis == 0
        msg = _any_filter_active(m) ? "No charts match filters" : "No charts"
        set_string!(buf, content.x + 2, y, msg, tstyle(:warning, bold=true))
        y += 1
        if _any_filter_active(m)
            set_string!(buf, content.x + 2, y,
                "  f · filter   F · clear   (demo tools may be empty)",
                tstyle(:text_dim))
        end
    else
        first_i = m.library_scroll + 1
        last_i = min(nvis, m.library_scroll + capacity)
        for vi in first_i:last_i
            c = vis_charts[vi]
            abs_i = findfirst(x -> x.id == c.id, m.charts)
            abs_i = abs_i === nothing ? 0 : abs_i
            marker = abs_i == m.library_selected ? "▶" : " "
            act = abs_i == m.active ? "*" : " "
            nvals = length(c.data.values)
            live = c.live_enabled ? "live" : "off"
            line = "$marker$act $abs_i. $(c.name)  [$(c.chart_type)] n=$nvals live=$live"
            sty = abs_i == m.library_selected ? tstyle(:accent, bold=true) : tstyle(:text)
            set_string!(buf, content.x + 2, y, line, sty)
            y += 1
        end
    end
    # Prompts / last_event live in Message chrome (shared style with dashboard)
    if chrome !== nothing
        _render_mode_chrome!(buf, chrome, m; mode=:library)
    end
end

# ── Tools registry page (P2-PR4) — master list m.tools; assign via builder ─
function _render_tools_page!(buf, area, m)
    content, chrome = _split_mode_chrome(area)
    m.tools_area = content
    set_string!(buf, content.x + 1, content.y,
        "TOOLS REGISTRY  ·  Esc/q → dashboard", tstyle(:title, bold=true))
    y = content.y + 2
    ntools = length(m.tools)
    if ntools >= 1
        m.tools_selected = clamp(m.tools_selected, 1, ntools)
    end
    set_string!(buf, content.x + 2, y,
        "Tools: $ntools   selected=$(m.tools_selected)   (registry ≠ chart tools list)",
        tstyle(:text_dim))
    y += 2
    capacity = _tools_visible_capacity(m)
    _sync_tools_scroll!(m, ntools, capacity)
    if ntools == 0
        set_string!(buf, content.x + 2, y, "No tools — a · add", tstyle(:warning, bold=true))
        y += 1
        set_string!(buf, content.x + 2, y,
            "  Master ids only; assign tools to charts via builder field Tools.",
            tstyle(:text_dim))
    else
        first_i = m.tools_scroll + 1
        last_i = min(ntools, m.tools_scroll + capacity)
        for i in first_i:last_i
            t = m.tools[i]
            marker = i == m.tools_selected ? "▶" : " "
            desc = isempty(t.description) ? "—" : t.description
            line = "$marker $i. $(t.id)  $desc"
            sty = i == m.tools_selected ? tstyle(:accent, bold=true) : tstyle(:text)
            set_string!(buf, content.x + 2, y, line, sty)
            y += 1
        end
    end
    if chrome !== nothing
        _render_mode_chrome!(buf, chrome, m; mode=:tools)
    end
end

# ── Config full-page (view_mode=:config; Rules / Lines / Visual) ─────────
"""Draw section body for Config page into `content` starting at row `y`. Returns next free y."""
function _render_config_section_body!(buf, content, m; y::Int)
    bot = bottom(content)
    if m.config_tab == :lines
        for (idx, key) in enumerate(CHART_LINE_KEYS)
            y > bot && break
            sel = idx == m.config_selected ? "▶ " : "  "
            on = get(m.show_chart_lines, key, true)
            bub = on ? "●" : "○"
            lbl = get(CHART_LINE_LABELS, key, key)
            st_lbl = get(LINE_STYLE_LABELS, _line_style(m, key), _line_style(m, key))
            set_string!(buf, content.x + 2, y, "$sel$idx $bub $lbl  $(on ? "[ON]" : "[OFF]")  $st_lbl",
                idx == m.config_selected ? tstyle(:accent, bold=true) : tstyle(:text))
            y += 1
        end
    elseif m.config_tab == :visual
        set_string!(buf, content.x + 2, y, "Graph visual prefs (add more over time):", tstyle(:text_dim))
        y += 1
        for (idx, key) in enumerate(VISUAL_PREF_KEYS)
            y > bot && break
            sel = idx == m.config_selected ? "▶ " : "  "
            on = _pref_on(m, key)
            bub = on ? "●" : "○"
            lbl = get(VISUAL_PREF_LABELS, key, key)
            set_string!(buf, content.x + 2, y, "$sel$idx $bub $lbl  $(on ? "[ON]" : "[OFF]")",
                idx == m.config_selected ? tstyle(:accent, bold=true) : tstyle(:text))
            y += 1
        end
    else
        for (idx, rid) in enumerate(["WECO-1","WECO-2","WECO-3","WECO-4","WECO-5","WECO-6","WECO-7","WECO-8"])
            y > bot && break
            sel = idx == m.config_selected ? "▶ " : "  "
            on = get(m.enabled_rules, rid, false) ? "[ON]" : "[OFF]"
            desc = get(WECO_RULE_DESCS, idx, "")
            set_string!(buf, content.x + 2, y, "$sel$rid $on $desc",
                idx == m.config_selected ? tstyle(:accent, bold=true) : tstyle(:text))
            y += 1
        end
    end
    return y
end

"""Full-page Config: Rules / Lines / Visual via `_split_mode_chrome` (no plot overlay)."""
function _render_config_page!(buf, area, m)
    content, chrome = _split_mode_chrome(area)
    set_string!(buf, content.x + 1, content.y,
        "CONFIG  ·  Esc/q → dashboard", tstyle(:title, bold=true))
    y = content.y + 1
    # Section strip — current tab bold; PR2 has three tabs only (no Saved)
    rules_sty = m.config_tab == :weco ? tstyle(:accent, bold=true) : tstyle(:text_dim)
    lines_sty = m.config_tab == :lines ? tstyle(:accent, bold=true) : tstyle(:text_dim)
    visual_sty = m.config_tab == :visual ? tstyle(:accent, bold=true) : tstyle(:text_dim)
    set_string!(buf, content.x + 2, y, "[Rules]", rules_sty)
    set_string!(buf, content.x + 12, y, "[Lines]", lines_sty)
    set_string!(buf, content.x + 22, y, "[Visual]", visual_sty)
    set_string!(buf, content.x + 34, y, "Tab cycle · ←/→ style · e presets menu", tstyle(:text_dim))
    y += 1
    tab_lbl = m.config_tab == :lines ? "Chart Lines" :
              (m.config_tab == :visual ? "Visual Preferences" : "WECO Rules")
    chname = isempty(m.charts) ? "—" : current_chart(m).name
    set_string!(buf, content.x + 2, y,
        "Section: $tab_lbl   ·  Active chart: $chname   ·  toggles apply immediately",
        tstyle(:text_dim))
    y += 2
    _render_config_section_body!(buf, content, m; y = y)
    if chrome !== nothing
        _render_mode_chrome!(buf, chrome, m; mode=:config)
    end
    return nothing
end

# ── Unified Graph Presets page — save popup + load selected ─────────────
"""Draw the named presets list body into `content` starting at row `y`. Returns next free y."""
function _render_presets_list_body!(buf, content, m; y::Int)
    npre = length(m.graph_presets)
    if npre >= 1
        m.presets_selected = clamp(m.presets_selected, 1, npre)
    end
    set_string!(buf, content.x + 2, y,
        "Presets: $npre   selected=$(m.presets_selected)   (whole set: lines · styles · visual · WECO)",
        tstyle(:text_dim))
    y += 2
    capacity = _presets_visible_capacity(m)
    _sync_presets_scroll!(m, npre, capacity)
    if npre == 0
        set_string!(buf, content.x + 2, y, "No presets — s · save current graph set", tstyle(:warning, bold=true))
        y += 1
        set_string!(buf, content.x + 2, y,
            "  Capture lines on/off, styles, visual prefs, and WECO rules under a name.",
            tstyle(:text_dim))
        y += 1
    else
        first_i = m.presets_scroll + 1
        last_i = min(npre, m.presets_scroll + capacity)
        for i in first_i:last_i
            p = m.graph_presets[i]
            marker = i == m.presets_selected ? "▶" : " "
            # Compact summary of what the preset holds
            n_off = count(!, values(p.show_chart_lines))
            n_rules = count(values(p.enabled_rules))
            line = "$marker $i. $(p.name)  (lines-off=$n_off · WECO-on=$n_rules)"
            sty = i == m.presets_selected ? tstyle(:accent, bold=true) : tstyle(:text)
            set_string!(buf, content.x + 2, y, line, sty)
            y += 1
        end
    end
    return y
end

function _render_presets_page!(buf, area, m)
    content, chrome = _split_mode_chrome(area)
    m.presets_area = content
    set_string!(buf, content.x + 1, content.y,
        "GRAPH PRESETS  ·  Esc/q → dashboard", tstyle(:title, bold=true))
    y = content.y + 2
    _render_presets_list_body!(buf, content, m; y = y)
    if chrome !== nothing
        _render_mode_chrome!(buf, chrome, m; mode=:presets)
    end
end

# ── Dedicated Help page — Keys-style chip sections ──────────────────────
function _render_help_page!(buf, area, m)
    _render_styled_doc_page!(buf, area, m;
        title = "SPC WORKBENCH — HELP  ·  Esc/h close",
        mode = :help)
end

# ── Keyboard map page — same visual language as Keys panel ──────────────
function _render_keymap_page!(buf, area, m)
    _render_styled_doc_page!(buf, area, m;
        title = "KEYBOARD MAP + MOUSE  ·  Esc/k close",
        mode = :keymap)
end

# ── SharedTable grid page (P2-PR7 / KD-P2-20) — full page + mode chrome ─
function _render_table_page!(buf, area, m)
    content, chrome = _split_mode_chrome(area)
    m.table_area = content
    set_string!(buf, content.x + 1, content.y,
        "SHARED TABLE  ·  Esc/q close",
        tstyle(:title, bold = true))
    y = content.y + 2
    nr = length(m.table.rows)
    nc_all = length(m.table.columns)
    nc = _table_n_cols(m)
    cell_w = TABLE_DEFAULT_CELL_W
    row_cap = _table_visible_row_capacity(m)
    col_cap = _table_visible_col_capacity(m; cell_w = cell_w)
    _sync_table_scroll!(m; row_cap = row_cap, col_cap = col_cap)

    set_string!(buf, content.x + 2, y,
        "rows=$nr cols=$nc_all  cursor=($(_table_n_rows(m) > 0 ? m.table_row : 0),$(nc > 0 ? m.table_col : 0))  scroll=($(m.table_scroll_row),$(m.table_scroll_col))" *
        (nc_all > TABLE_MAX_RENDER_COLS ? "  (showing first $TABLE_MAX_RENDER_COLS cols)" : ""),
        tstyle(:text_dim))
    y += 1

    if nr == 0 || nc_all == 0
        set_string!(buf, content.x + 2, y + 1,
            "Empty table — import CSV (library i) or load session (library W)",
            tstyle(:warning, bold = true))
        y += 3
        set_string!(buf, content.x + 2, y,
            "  SharedTable is session data; rematerialize only via r · or builder apply.",
            tstyle(:text_dim))
    else
        c0 = m.table_scroll_col + 1
        c1 = min(nc, m.table_scroll_col + col_cap)
        hdr_parts = String["#"]
        for c in c0:c1
            name = m.table.columns[c]
            mark = c == m.table_col ? "▶" : " "
            push!(hdr_parts, mark * _table_cell_display(name, cell_w - 1))
        end
        set_string!(buf, content.x + 2, y, join(hdr_parts, " "), tstyle(:accent, bold = true))
        y += 1

        r0 = m.table_scroll_row + 1
        r1 = min(nr, m.table_scroll_row + row_cap)
        for r in r0:r1
            y > bottom(content) && break
            row_mark = r == m.table_row ? "▶" : " "
            parts = String[row_mark * lpad(string(r), 3)]
            for c in c0:c1
                val = _table_cell_value(m, r, c)
                if m.table_editing && r == m.table_row && c == m.table_col
                    val = m.table_buf * "▌"
                end
                cell = _table_cell_display(val, cell_w)
                if r == m.table_row && c == m.table_col && !m.table_editing
                    cell = _table_cell_display("[" * _table_cell_value(m, r, c) * "]", cell_w)
                end
                push!(parts, cell)
            end
            sty = r == m.table_row ? tstyle(:accent, bold = true) : tstyle(:text)
            set_string!(buf, content.x + 2, y, join(parts, " "), sty)
            y += 1
        end
    end
    if chrome !== nothing
        _render_mode_chrome!(buf, chrome, m; mode=:table)
    end
end

# ── Builder page (PR6) — form + shared Message|Keys chrome ──────────────
function _render_builder_page!(buf, area, m)
    _ensure_charts!(m)
    content, chrome = _split_mode_chrome(area)
    ch = current_chart(m)
    set_string!(buf, content.x + 1, content.y,
        "BUILDER — $(ch.name)  ·  Esc/q close",
        tstyle(:title, bold = true))
    y = content.y + 2
    for (i, field) in enumerate(BUILDER_FIELDS)
        y > bottom(content) - 2 && break
        sel = i == m.builder_selected ? "▶ " : "  "
        lbl = get(BUILDER_FIELD_LABELS, field, string(field))
        val = if m.builder_editing && i == m.builder_selected
            m.builder_buf * "▌"
        else
            v = _builder_field_value(ch, field)
            isempty(v) ? "—" : v
        end
        sty = i == m.builder_selected ? tstyle(:accent, bold = true) : tstyle(:text)
        set_string!(buf, content.x + 2, y, "$sel$i $lbl: $val", sty)
        y += 1
    end
    y += 1
    if y <= bottom(content)
        weco_parts = String[]
        for i in 1:8
            rid = "WECO-$i"
            on = get(ch.enabled_rules, rid, false)
            push!(weco_parts, on ? "$(i)●" : "$(i)○")
        end
        set_string!(buf, content.x + 2, y, "WECO: " * join(weco_parts, " "), tstyle(:text))
        y += 1
    end
    if y <= bottom(content)
        nrows = length(m.table.rows)
        ncols = length(m.table.columns)
        set_string!(buf, content.x + 2, y,
            "Table: $nrows rows · $ncols cols · source=$(ch.source) · live=$(ch.live_enabled)",
            tstyle(:text_dim))
    end
    if chrome !== nothing
        _render_mode_chrome!(buf, chrome, m; mode=:builder)
    end
end

# Enhance footer with current chart + mode
# (footer render already at end of view; header now mentions keys)

# WECO rule descs (for overlay)
const WECO_RULE_DESCS = [
    "1 point beyond 3σ",
    "2 of 3 consec. zone A (>2σ)",
    "4 of 5 consec. zone B (>1σ)",
    "8 in a row same side CL",
    "6 in a row trending",
    "14 alternating",
    "15 inside 1σ",
    "8 outside 1σ",
]

# ── Live (slice 6) — PR3: per-chart live_enabled + modal gates ─────────

"""Shared predicate for view tick path and advance_live! (defensive)."""
function _live_may_advance(m::SPCWorkbenchModel)::Bool
    m.paused && return false
    m.editing !== nothing && return false
    m.config_open && return false
    m.prompt_kind !== nothing && return false
    m.pending_delete && return false
    m.view_mode in (:help, :keymap, :library, :builder, :tools, :table, :presets, :config) && return false
    ch = current_chart(m)
    (isempty(ch.data.values) || !ch.live_enabled) && return false
    return true
end

function advance_live!(m::SPCWorkbenchModel)
    _live_may_advance(m) || return
    n = length(m.data.values)
    if n >= m.live_max || n == 0
        return
    end
    last = m.data.values[end]
    nextv = 0.6 * last + 0.4 * m.data.cl + m.data.sigma * 0.8 * randn(m.rng)
    if rand(m.rng) < 0.04
        nextv += 3.2 * m.data.sigma
    end
    push!(m.data.values, nextv)
    # recompute cl/sigma lightly for demo
    m.data.cl = mean(m.data.values)
    m.data.sigma = std(m.data.values; corrected=true)
    # note: view will call weco with current rules
end

append_live_point!(m::SPCWorkbenchModel) = advance_live!(m)

# Map helpers (for completeness)
if !isdefined(@__MODULE__, :map_to_dot_x)
function map_to_dot_x(idx::Int, vp::Viewport, dot_w::Int)
    span = vp.x1 - vp.x0
    span == 0 && return 0
    t = (idx - vp.x0) / span
    round(Int, 0 + t * (dot_w - 1))
end

function map_to_dot_y(val::Float64, vp::Viewport, dot_h::Int)
    span = vp.yhi - vp.ylo
    span == 0 && return dot_h ÷ 2
    t = (val - vp.ylo) / span
    round(Int, (dot_h - 1) - t * (dot_h - 1))
end
end

# Ensure dashed_line! always available for workbench view (shared guard may skip in some include orders)
if !isdefined(@__MODULE__, :dashed_line!)
function dashed_line!(c, x0::Int, y0::Int, x1::Int, y1::Int; dash::Int = 4)
    dx = abs(x1 - x0); dy = abs(y1 - y0)
    sx = x0 < x1 ? 1 : -1; sy = y0 < y1 ? 1 : -1
    err = dx - dy
    step = 0
    while true
        if (step ÷ dash) % 2 == 0
            set_point!(c, x0, y0)
        end
        (x0 == x1 && y0 == y1) && break
        e2 = 2 * err
        if e2 > -dy; err -= dy; x0 += sx; end
        if e2 < dx; err += dx; y0 += sy; end
        step += 1
    end
end
end

# ── Runners (slice 7) ───────────────────────────────────────────────────

"""
    spc_workbench_demo()

Static/paused public runner.
"""
function spc_workbench_demo(;
    load::Union{Nothing,AbstractString} = nothing,
    seed_demos::Symbol = :triple,
    value_col::String = "Value",
)
    d = generate_spc_workbench_data(40; seed=42)
    n = length(d.values)
    vp = Viewport(x0 = n > 0 ? 1 : 0, x1 = n > 0 ? n : 0)
    if n > 0
        lz = compute_limits_and_zones(d.values; sigma_method = :mr)
        auto_fit_viewport_y!(vp, d.values, lz)
    end
    m = SPCWorkbenchModel(data = d, viewport = vp, paused = true, seed_demos = seed_demos)
    if n > 0
        clamp_viewport!(m.viewport, n)
    end
    _ensure_charts!(m)
    if load !== nothing
        import_csv_new_chart!(m, load; value_col = value_col)
        # import forces paused=true; keep demo static
        m.paused = true
    end
    app(m)
end

const run_spc_workbench = spc_workbench_demo

"""
    spc_workbench(; paused=false, load=nothing, workbench=nothing, seed_demos=:triple, value_col="Value")

Live/interactive workbench.
- `workbench=` loads schema-v1 JSON via `load_workbench` (construct) before `app(m)`.
- `load=` imports a CSV series as a new chart (live_enabled=false, activated, paused=true).
`seed_demos` default remains `:triple` — never flip.
"""
function spc_workbench(;
    paused::Bool = false,
    load::Union{Nothing,AbstractString} = nothing,
    workbench::Union{Nothing,AbstractString} = nothing,
    seed_demos::Symbol = :triple,
    value_col::String = "Value",
)
    if workbench !== nothing
        m_or_err = load_workbench(workbench)
        m_or_err isa AbstractString && error(m_or_err)
        m = m_or_err
        if paused
            m.paused = true
        end
        if load !== nothing
            import_csv_new_chart!(m, load; value_col = value_col)
            m.paused = true
        end
        app(m)
        return
    end
    d = generate_spc_workbench_data(40; seed=42)
    n = length(d.values)
    vp = Viewport(x0 = n > 0 ? 1 : 0, x1 = n > 0 ? n : 0)
    if n > 0
        lz = compute_limits_and_zones(d.values; sigma_method = :mr)
        auto_fit_viewport_y!(vp, d.values, lz)
    end
    m = SPCWorkbenchModel(data = d, viewport = vp, paused = paused, seed_demos = seed_demos)
    if n > 0
        clamp_viewport!(m.viewport, n)
    end
    _ensure_charts!(m)
    if load !== nothing
        import_csv_new_chart!(m, load; value_col = value_col)
        # successful import sets paused=true; failed import leaves seed charts
    end
    app(m)
end

const advanced_spc = spc_workbench
const run_advanced_spc = spc_workbench

# Ensure TachikomaTUI can see the new symbols when included
# (exports happen in TachikomaTUI.jl)
