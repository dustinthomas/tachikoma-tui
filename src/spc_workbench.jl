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

# Extensible graph visual preferences (add keys over time; panel lists VISUAL_PREF_KEYS)
const VISUAL_PREF_KEYS = ["solid_series", "solid_stroke", "braille_series"]
const VISUAL_PREF_LABELS = Dict{String,String}(
    "solid_series" => "Dotted series (• connect)",
    "solid_stroke" => "Solid stroke (box-drawing)",
    "braille_series" => "Braille canvas line (between dots)",
)
const DEFAULT_VISUAL_PREFS = Dict{String,Bool}(
    "solid_series" => true,
    "solid_stroke" => true,
    "braille_series" => true,
)

_pref_on(m, key::AbstractString) = get(m.visual_prefs, key, get(DEFAULT_VISUAL_PREFS, key, false))

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

struct ChartRenderContext
    lz::LimitsAndZones
    viol_indices::Set{Int}
    cpk::Union{Float64,Nothing}
    band::Symbol
end

"""
    auto_limits(vs; chart_type=I_MR, subgroup_size=5, sigma_method=:mr)

PR1 thin alias to `compute_limits_and_zones` (I-MR / :mr path).
PR7 fills type-aware auto (X̄-R/S, attributes); kwargs reserved as the hook.
"""
function auto_limits(
    vs;
    chart_type::ChartType = I_MR,
    subgroup_size::Int = 5,
    sigma_method::Symbol = :mr,
)::LimitsAndZones
    # PR1: ignore chart_type / subgroup_size; always existing I-MR path
    compute_limits_and_zones(vs; sigma_method = sigma_method)
end

"""
    resolve_chart_render_context(ch; sigma_method=:mr)

Pure resolver gateway. Returns canonical lz (with chosen sigma), WECO viol set, cpk, band.
All OOC/OOS/Cpk decisions and labels must derive from this to guarantee consistency.

PR1 skeleton: branches on `limits_mode` / `chart_type` but all paths still I_MR/:mr.
PR5 fills manual limits; PR7 fills type-aware auto.
"""
function resolve_chart_render_context(ch::ChartSpec; sigma_method::Symbol = :mr)::ChartRenderContext
    vs = ch.data.values
    # PR1 skeleton — all paths currently reduce to I_MR/:mr behavior:
    if ch.limits_mode == :manual &&
       ch.manual_cl !== nothing && ch.manual_ucl !== nothing && ch.manual_lcl !== nothing
        # PR5 fills: sigma = (ucl - cl) / 3; zones from that sigma
        # Until PR5: fall through to auto
        lz = auto_limits(vs; chart_type = ch.chart_type, subgroup_size = ch.subgroup_size,
                         sigma_method = sigma_method)
    else
        # PR7 fills type-aware auto; until then always I_MR :mr path via auto_limits
        lz = auto_limits(vs; chart_type = ch.chart_type, subgroup_size = ch.subgroup_size,
                         sigma_method = sigma_method)
    end
    viols = weco_detect(vs, lz.cl, lz.sigma; enabled_rules = ch.enabled_rules)
    viol_set = Set(v.index for v in viols)
    cr = compute_capability(vs, lz.cl, lz.sigma; usl = ch.usl, lsl = ch.lsl)
    b = cpk_band(cr.cpk)
    ChartRenderContext(lz, viol_set, cr.cpk, b)
end

"""
    point_status(i, ctx, ch) -> :oos | :ooc | :ok

Canonical classification for a point. Used by hover labels and marker choice.
"""
function point_status(i::Int, ctx::ChartRenderContext, ch::ChartSpec)::Symbol
    n = length(ch.data.values)
    if i < 1 || i > n
        return :ok
    end
    v = ch.data.values[i]
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
export DEFAULT_WECO_RULES, DEFAULT_CHART_LINES, CHART_LINE_KEYS
export DEFAULT_VISUAL_PREFS, VISUAL_PREF_KEYS
export ChartType, ChartSpec, empty_workbench_data, CHART_TYPE_WIRE, parse_chart_type, chart_type_to_string
export I_MR, Xbar_R, Xbar_S, p_chart, np_chart, c_chart, u_chart

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
    # enabled_rules carried for live/config
    enabled_rules::Dict{String, Bool} = copy(DEFAULT_WECO_RULES)
    # Chart line visibility (CL / ±1σ / ±2σ / ±3σ / Specs)
    show_chart_lines::Dict{String, Bool} = copy(DEFAULT_CHART_LINES)
    # Graph visual preferences (extensible panel; start with solid series line)
    visual_prefs::Dict{String, Bool} = copy(DEFAULT_VISUAL_PREFS)
    # Dashboard multi-chart (AC2/AC3)
    charts::Vector{ChartSpec} = ChartSpec[]
    active::Int = 1
    library_selected::Int = 1
    view_mode::Symbol = :dashboard   # :dashboard, :focused, :help, :keymap
    # Seed policy when charts empty — NEVER flip default from :triple
    seed_demos::Symbol = :triple     # :triple | :single | :none
    tools::Vector{ToolEntry} = ToolEntry[]
    # Prefill only for save/load prompts — never silent write to default path
    last_workbench_path::String = ""
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

# ── Pure chart library CRUD ─────────────────────────────────────────────

"""
    add_chart!(m; name="New chart", data=empty_workbench_data()) -> Int

Append a valid ChartSpec. Returns new 1-based index. Sets library_selected;
does not change active unless charts was empty.
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
        enabled_rules = copy(DEFAULT_WECO_RULES),
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

export ToolEntry, add_chart!, clone_chart!, delete_chart!, rename_chart!, set_active_chart!

# ── Update (Key + Mouse, full fidelity) ─────────────────────────────────

function update!(m::SPCWorkbenchModel, evt::KeyEvent)
    _ensure_charts!(m)
    ch = current_chart(m)
    n = length(m.data.values)

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

    # config / editing handling (slice 4+)
    if m.config_open
        if evt.key == :escape || (evt.key == :char && (evt.char == 'c' || evt.char == 'C' ||
                evt.char == 'v' || evt.char == 'V' || evt.char == 'o' || evt.char == 'O'))
            m.config_open = false
            m.last_event = "config closed"
            return
        end
        # Tab cycles WECO → Lines → Visual → WECO
        if evt.key == :tab || (evt.key == :char && evt.char == '\t')
            m.config_tab = m.config_tab == :weco ? :lines : (m.config_tab == :lines ? :visual : :weco)
            m.config_selected = 1
            m.last_event = "config tab $(m.config_tab)"
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
        end
        return
    end

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

    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end

    if evt.key == :char
        c = evt.char
        if c == 'p' || c == 'P'
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
            m.config_open = !m.config_open
            m.config_tab = :weco
            m.config_selected = 1
            m.last_event = m.config_open ? "config open" : "config close"
            return
        elseif c == 'v' || c == 'V'
            # Open config directly on chart-lines tab
            m.config_open = true
            m.config_tab = :lines
            m.config_selected = 1
            m.last_event = "config lines"
            return
        elseif c == 'o' || c == 'O'
            # Open Visual Preferences panel (extensible graph prefs)
            m.config_open = true
            m.config_tab = :visual
            m.config_selected = 1
            m.last_event = "config visual"
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
        elseif c == '?' || c == 'h' || c == 'H'
            m.view_mode = :help
            m.last_event = "help open"
            return
        elseif c == 'k' || c == 'K'
            m.view_mode = :keymap
            m.last_event = "keymap open"
            return
        elseif c == ']' || c == '>'
            m.active = min(length(m.charts), m.active + 1)
            _ensure_charts!(m)
            m.last_event = "chart $(m.active)"
            return
        elseif c == '[' || c == '<'
            m.active = max(1, m.active - 1)
            _ensure_charts!(m)
            m.last_event = "chart $(m.active)"
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
    if m.config_open || m.editing !== nothing || m.view_mode == :help || m.view_mode == :keymap
        m.last_event = string(evt.action, " ", evt.button, " (modal)")
        m.hover_x = nothing
        m.hovered = nothing
        if evt.action == mouse_release
            m.drag_start = nothing
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
        set_string!(buf, area.x, area.y, m.config_open ? "config open [c/Esc]" : "SPC Workbench (small)", tstyle(:text_dim))
        return
    end

    # Mode overlays: help / keymap (new dedicated pages)
    if m.view_mode == :help
        _render_help_page!(buf, area, m)
        return
    elseif m.view_mode == :keymap
        _render_keymap_page!(buf, area, m)
        return
    end

    # layout
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(3), Fixed(1)]), area)
    if length(rows) < 4
        return
    end
    header = rows[1]
    main = rows[2]
    gauge_row = rows[3]
    footer = rows[4]

    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(28)]), main)
    if length(cols) < 2
        return
    end
    plot_rect = cols[1]
    side_rect = cols[2]

    # Dashboard: render multiple (up to 3) charts simultaneously for rich visual
    ncharts = length(m.charts)
    is_dashboard_multi = (m.view_mode == :dashboard && ncharts >= 2)
    active_plot_rect = plot_rect
    second_plot_rect = nothing
    third_plot_rect = nothing
    if is_dashboard_multi
        nc = min(3, ncharts)
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

    # header
    hdr = "SPC Workbench [dashboard]  [p]pause [g]live [r]reset [c]config [u/t/l/s]specs [1-8]rules [h]help [k]keys [[]]chart [q]quit"
    set_string!(buf, header.x + 1, header.y, hdr, tstyle(:title, bold=true))

    if m.config_open
        # overlay (slice 4) — no bleed; Tab cycles WECO → Lines → Visual
        ov = plot_rect
        ov_h = max(6, min(ov.height - 2, 14))
        ov_rect = Rect(ov.x + 2, ov.y + 1, ov.width - 4, ov_h)
        tab_lbl = m.config_tab == :lines ? "Chart Lines" : (m.config_tab == :visual ? "Visual Preferences" : "WECO Rules")
        cfg = Block(title="Config: $tab_lbl (Tab switch · ↑↓ · 1-N space/enter · Esc/c/v/o close)", border_style=tstyle(:accent, bold=true))
        inner = render(cfg, ov_rect, buf)
        # clear
        for yy in inner.y:bottom(inner)
            for xx in inner.x:right(inner)
                set_char!(buf, xx, yy, ' ', tstyle(:text))
            end
        end
        y = inner.y + 1
        if m.config_tab == :lines
            for (idx, key) in enumerate(CHART_LINE_KEYS)
                if y > bottom(inner) - 1
                    break
                end
                sel = idx == m.config_selected ? "▶ " : "  "
                on = get(m.show_chart_lines, key, true)
                bub = on ? "●" : "○"
                lbl = get(CHART_LINE_LABELS, key, key)
                set_string!(buf, inner.x + 1, y, "$sel$idx $bub $lbl  $(on ? "[ON]" : "[OFF]")  (draw on chart)", idx == m.config_selected ? tstyle(:accent, bold=true) : tstyle(:text))
                y += 1
            end
        elseif m.config_tab == :visual
            set_string!(buf, inner.x + 1, y, "Graph visual prefs (add more over time):", tstyle(:text_dim))
            y += 1
            for (idx, key) in enumerate(VISUAL_PREF_KEYS)
                if y > bottom(inner) - 1
                    break
                end
                sel = idx == m.config_selected ? "▶ " : "  "
                on = _pref_on(m, key)
                bub = on ? "●" : "○"
                lbl = get(VISUAL_PREF_LABELS, key, key)
                set_string!(buf, inner.x + 1, y, "$sel$idx $bub $lbl  $(on ? "[ON]" : "[OFF]")", idx == m.config_selected ? tstyle(:accent, bold=true) : tstyle(:text))
                y += 1
            end
        else
            for (idx, rid) in enumerate(["WECO-1","WECO-2","WECO-3","WECO-4","WECO-5","WECO-6","WECO-7","WECO-8"])
                if y > bottom(inner) - 1
                    break
                end
                sel = idx == m.config_selected ? "▶ " : "  "
                on = get(m.enabled_rules, rid, false) ? "[ON]" : "[OFF]"
                desc = get(WECO_RULE_DESCS, idx, "")
                set_string!(buf, inner.x + 1, y, "$sel$rid $on $desc", idx == m.config_selected ? tstyle(:accent, bold=true) : tstyle(:text))
                y += 1
            end
        end
        return
    end

    # normal (or dashboard multi) render for active
    chname = isempty(m.charts) ? "Data" : current_chart(m).name
    empty_hint = (n == 0) ? " — No data — import CSV or clone a demo" : ""
    plot_block = Block(title = "Dashboard: $(chname) [$(m.active)/$(length(m.charts))] (│ hover  ┃ select  drag pan  wheel zoom)  [ ] switch$(empty_hint)", border_style = tstyle(:border), title_style = tstyle(:title))
    plot_inner = render(plot_block, active_plot_rect, buf)
    m.plot_area = plot_inner

    cw = plot_inner.width
    ch = plot_inner.height

    if cw > 0 && ch > 0 && n > 0
        ch_act = current_chart(m)
        ctx = resolve_chart_render_context(ch_act; sigma_method = :mr)
        viol_set = ctx.viol_indices
        lz_disp = ctx.lz   # canonical mr-based
        # Auto-scale Y so visible points + enabled limit/spec lines stay inside the plot
        auto_fit_viewport_y!(m.viewport, m.data.values, lz_disp;
            usl = m.usl, lsl = m.lsl, show_lines = m.show_chart_lines)
        ch_act.viewport = m.viewport

        c = create_canvas(cw, ch; style = !isempty(viol_set) ? tstyle(:accent) : tstyle(:primary))
        dw, dh = canvas_dot_size(c)

        prev = nothing
        for i in m.viewport.x0:m.viewport.x1
            if i < 1 || i > n
                continue
            end
            v = m.data.values[i]
            dx = map_to_dot_x(i, m.viewport, dw)
            dy = map_to_dot_y(v, m.viewport, dh)
            set_point!(c, dx, dy)
            if prev !== nothing && _pref_on(m, "braille_series")
                line!(c, prev[1], prev[2], dx, dy)
            end
            prev = (dx, dy)
        end

        # limits + zones (slice 5) -- use MR disp; gated by show_chart_lines
        lz = lz_disp
        if _line_on(m, "sigma1")
            for (z, dash) in [(lz.ucl1, 2), (lz.lcl1, 2)]
                zy = map_to_dot_y(z, m.viewport, dh)
                dashed_line!(c, 0, zy, dw-1, zy; dash = dash)
            end
        end
        if _line_on(m, "sigma2")
            for (z, dash) in [(lz.ucl2, 3), (lz.lcl2, 3)]
                zy = map_to_dot_y(z, m.viewport, dh)
                dashed_line!(c, 0, zy, dw-1, zy; dash = dash)
            end
        end
        if _line_on(m, "sigma3")
            dashed_line!(c, 0, map_to_dot_y(lz.ucl, m.viewport, dh), dw-1, map_to_dot_y(lz.ucl, m.viewport, dh); dash=4)
            dashed_line!(c, 0, map_to_dot_y(lz.lcl, m.viewport, dh), dw-1, map_to_dot_y(lz.lcl, m.viewport, dh); dash=4)
        end
        if _line_on(m, "cl")
            line!(c, 0, map_to_dot_y(lz.cl, m.viewport, dh), dw-1, map_to_dot_y(lz.cl, m.viewport, dh))
        end

        # spec lines if set (slice 5)
        if _line_on(m, "specs")
            if m.usl !== nothing
                sy = map_to_dot_y(m.usl, m.viewport, dh)
                dashed_line!(c, 0, sy, dw-1, sy; dash=2)
            end
            if m.lsl !== nothing
                sy = map_to_dot_y(m.lsl, m.viewport, dh)
                dashed_line!(c, 0, sy, dw-1, sy; dash=2)
            end
        end

        render_canvas(c, plot_inner, f)

        # Colorized limit/zone/spec lines (distinct styles; gated by show_chart_lines)
        lz_c = lz_disp  # already :mr
        function _draw_lim_line!(rect, val, sty, step=3)
            yy = data_val_to_cell_row(val, rect, m.viewport)
            for xx in rect.x:right(rect)
                if (xx % step) == 0
                    set_char!(buf, xx, yy, '-', sty)
                end
            end
        end
        if _line_on(m, "specs")
            if m.usl !== nothing; _draw_lim_line!(plot_inner, m.usl, tstyle(:error, bold=true), 2); end
            if m.lsl !== nothing; _draw_lim_line!(plot_inner, m.lsl, tstyle(:error, bold=true), 2); end
        end
        if _line_on(m, "sigma3")
            _draw_lim_line!(plot_inner, lz_c.ucl, tstyle(:warning, bold=true), 4)
            _draw_lim_line!(plot_inner, lz_c.lcl, tstyle(:warning, bold=true), 4)
        end
        if _line_on(m, "sigma2")
            _draw_lim_line!(plot_inner, lz_c.ucl2, tstyle(:secondary), 3)
            _draw_lim_line!(plot_inner, lz_c.lcl2, tstyle(:secondary), 3)
        end
        if _line_on(m, "sigma1")
            _draw_lim_line!(plot_inner, lz_c.ucl1, tstyle(:text_dim), 2)
            _draw_lim_line!(plot_inner, lz_c.lcl1, tstyle(:text_dim), 2)
        end
        if _line_on(m, "cl")
            cly = data_val_to_cell_row(lz_c.cl, plot_inner, m.viewport)
            for xx in plot_inner.x:right(plot_inner); set_char!(buf, xx, cly, '─', tstyle(:accent)); end
        end

        # overlays (fidelity)
        if m.hover_x !== nothing
            hx = clamp(m.hover_x, plot_inner.x, right(plot_inner))
            for y in (plot_inner.y+1):(bottom(plot_inner)-1)
                set_char!(buf, hx, y, '│', tstyle(:accent))
            end
        end
        if (si = m.selected) !== nothing && 1 <= si <= n && si >= m.viewport.x0 && si <= m.viewport.x1
            hx = data_index_to_cell(si, plot_inner, m.viewport)
            for y in (plot_inner.y+1):(bottom(plot_inner)-1)
                set_char!(buf, hx, y, '┃', tstyle(:secondary, bold=true))
            end
        end
        if (hi = m.hovered) !== nothing && 1 <= hi <= n && hi >= m.viewport.x0 && hi <= m.viewport.x1
            hy = data_val_to_cell_row(m.data.values[hi], plot_inner, m.viewport)
            set_char!(buf, plot_inner.x + 1, hy, '─', tstyle(:accent))
        end

        # Series connectors (visual prefs): dotted • and/or solid box-drawing stroke
        draw_series_connectors!(buf, plot_inner, m.data.values, m.viewport, m)

        # markers
        for i in m.viewport.x0:m.viewport.x1
            if i < 1 || i > n
                continue
            end
            dx = data_index_to_cell(i, plot_inner, m.viewport)
            dy = data_val_to_cell_row(m.data.values[i], plot_inner, m.viewport)
            is_v = i in viol_set
            vval = m.data.values[i]
            is_oos = (m.usl !== nothing && vval > m.usl) || (m.lsl !== nothing && vval < m.lsl)
            if is_oos
                sym = '✕'
                sty = tstyle(:error, bold=true)
            else
                sym = is_v ? '◆' : '●'
                sty = is_v ? tstyle(:accent, bold=true) : tstyle(:primary, bold=true)
            end
            set_char!(buf, dx, dy, sym, sty)
        end

        # tooltip
        if (hi = m.hovered) !== nothing && hi >= m.viewport.x0 && hi <= m.viewport.x1 && m.drag_start === nothing
            draw_hover_tooltip!(buf, plot_inner, hi, m.data.values[hi], hi in viol_set, m.viewport; usl=m.usl, target=m.target, lsl=m.lsl)
        end

        # labels
        set_string!(buf, plot_inner.x, plot_inner.y + ch - 1, string(m.viewport.x0), tstyle(:text_dim))
        set_string!(buf, right(plot_inner)-3, plot_inner.y + ch - 1, string(m.viewport.x1), tstyle(:text_dim))
    end

    # SECOND simultaneous chart for dashboard (rich multi visible)
    if is_dashboard_multi && second_plot_rect !== nothing && length(m.charts) >= 2
        ch2 = m.charts[2]
        n2 = length(ch2.data.values)
        if n2 > 0 && second_plot_rect.width > 4 && second_plot_rect.height > 3
            blk2 = Block(title = "Chart 2: $(ch2.name) (read-only view)", border_style = tstyle(:border), title_style = tstyle(:text_dim))
            inn2 = render(blk2, second_plot_rect, buf)
            cw2, ch2h = inn2.width, inn2.height
            if cw2 > 0 && ch2h > 0
                ctx2 = resolve_chart_render_context(ch2; sigma_method=:mr)
                viol2 = ctx2.viol_indices
                auto_fit_viewport_y!(ch2.viewport, ch2.data.values, ctx2.lz;
                    usl = ch2.usl, lsl = ch2.lsl, show_lines = m.show_chart_lines)
                c2 = create_canvas(cw2, ch2h; style = !isempty(viol2) ? tstyle(:accent) : tstyle(:primary))
                dw2, dh2 = canvas_dot_size(c2)
                prev2 = nothing
                vp2 = ch2.viewport
                for i in vp2.x0 : vp2.x1
                    (i<1 || i>n2) && continue
                    v = ch2.data.values[i]
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
                    for (z, dsh) in [(lz2.ucl1,2),(lz2.lcl1,2)]
                        zy = map_to_dot_y(z, vp2, dh2)
                        dashed_line!(c2, 0, zy, dw2-1, zy; dash=dsh)
                    end
                end
                if _line_on(m, "sigma2")
                    for (z, dsh) in [(lz2.ucl2,3),(lz2.lcl2,3)]
                        zy = map_to_dot_y(z, vp2, dh2)
                        dashed_line!(c2, 0, zy, dw2-1, zy; dash=dsh)
                    end
                end
                if _line_on(m, "sigma3")
                    dashed_line!(c2, 0, map_to_dot_y(lz2.ucl, vp2, dh2), dw2-1, map_to_dot_y(lz2.ucl, vp2, dh2); dash=4)
                    dashed_line!(c2, 0, map_to_dot_y(lz2.lcl, vp2, dh2), dw2-1, map_to_dot_y(lz2.lcl, vp2, dh2); dash=4)
                end
                if _line_on(m, "cl")
                    line!(c2, 0, map_to_dot_y(lz2.cl, vp2, dh2), dw2-1, map_to_dot_y(lz2.cl, vp2, dh2))
                end
                if _line_on(m, "specs")
                    if ch2.usl !== nothing
                        sy = map_to_dot_y(ch2.usl, vp2, dh2); dashed_line!(c2, 0, sy, dw2-1, sy; dash=2)
                    end
                    if ch2.lsl !== nothing
                        sy = map_to_dot_y(ch2.lsl, vp2, dh2); dashed_line!(c2, 0, sy, dw2-1, sy; dash=2)
                    end
                end
                render_canvas(c2, inn2, f)
                # Colorized overlays for ch2 (same as active; gated)
                function _draw_lim2!(r, v, st, stp=3)
                    yy = data_val_to_cell_row(v, r, vp2)
                    for xx in r.x:right(r)
                        if (xx % stp) == 0; set_char!(buf, xx, yy, '-', st); end
                    end
                end
                if _line_on(m, "specs")
                    if ch2.usl !== nothing; _draw_lim2!(inn2, ch2.usl, tstyle(:error, bold=true), 2); end
                    if ch2.lsl !== nothing; _draw_lim2!(inn2, ch2.lsl, tstyle(:error, bold=true), 2); end
                end
                if _line_on(m, "sigma3")
                    _draw_lim2!(inn2, lz2.ucl, tstyle(:warning, bold=true), 4)
                    _draw_lim2!(inn2, lz2.lcl, tstyle(:warning, bold=true), 4)
                end
                if _line_on(m, "sigma2")
                    _draw_lim2!(inn2, lz2.ucl2, tstyle(:secondary), 3)
                    _draw_lim2!(inn2, lz2.lcl2, tstyle(:secondary), 3)
                end
                if _line_on(m, "sigma1")
                    _draw_lim2!(inn2, lz2.ucl1, tstyle(:text_dim), 2)
                    _draw_lim2!(inn2, lz2.lcl1, tstyle(:text_dim), 2)
                end
                if _line_on(m, "cl")
                    cly2 = data_val_to_cell_row(lz2.cl, inn2, vp2)
                    for xx in inn2.x:right(inn2); set_char!(buf, xx, cly2, '─', tstyle(:accent)); end
                end
                draw_series_connectors!(buf, inn2, ch2.data.values, vp2, m)
                # markers for ch2 (OOC/OOS)
                for i in vp2.x0:vp2.x1
                    (i<1||i>n2) && continue
                    dx = data_index_to_cell(i, inn2, vp2)
                    dy = data_val_to_cell_row(ch2.data.values[i], inn2, vp2)
                    st2 = point_status(i, ctx2, ch2)
                    if st2 == :oos
                        sym2 = '✕'; sty2 = tstyle(:error, bold=true)
                    elseif st2 == :ooc
                        sym2 = '◆'; sty2 = tstyle(:accent, bold=true)
                    else
                        sym2 = '●'; sty2 = tstyle(:primary, bold=true)
                    end
                    set_char!(buf, dx, dy, sym2, sty2)
                end
            end
        end
    end

    # THIRD simultaneous chart when >=3
    if third_plot_rect !== nothing && ncharts >= 3
        ch3 = m.charts[3]
        n3 = length(ch3.data.values)
        if n3 > 0 && third_plot_rect.width > 4 && third_plot_rect.height > 3
            blk3 = Block(title = "Chart 3: $(ch3.name) (read-only)", border_style = tstyle(:border), title_style = tstyle(:text_dim))
            inn3 = render(blk3, third_plot_rect, buf)
            cw3, ch3h = inn3.width, inn3.height
            if cw3 > 0 && ch3h > 0
                ctx3 = resolve_chart_render_context(ch3; sigma_method=:mr)
                viol3 = ctx3.viol_indices
                auto_fit_viewport_y!(ch3.viewport, ch3.data.values, ctx3.lz;
                    usl = ch3.usl, lsl = ch3.lsl, show_lines = m.show_chart_lines)
                c3 = create_canvas(cw3, ch3h; style = !isempty(viol3) ? tstyle(:accent) : tstyle(:primary))
                dw3, dh3 = canvas_dot_size(c3)
                prev3 = nothing
                vp3 = ch3.viewport
                for i in vp3.x0:vp3.x1
                    (i<1 || i>n3) && continue
                    v = ch3.data.values[i]
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
                    for (z, dsh) in [(lz3.ucl1,2),(lz3.lcl1,2)]
                        zy = map_to_dot_y(z, vp3, dh3); dashed_line!(c3, 0, zy, dw3-1, zy; dash=dsh)
                    end
                end
                if _line_on(m, "sigma2")
                    for (z, dsh) in [(lz3.ucl2,3),(lz3.lcl2,3)]
                        zy = map_to_dot_y(z, vp3, dh3); dashed_line!(c3, 0, zy, dw3-1, zy; dash=dsh)
                    end
                end
                if _line_on(m, "sigma3")
                    dashed_line!(c3, 0, map_to_dot_y(lz3.ucl, vp3, dh3), dw3-1, map_to_dot_y(lz3.ucl, vp3, dh3); dash=4)
                    dashed_line!(c3, 0, map_to_dot_y(lz3.lcl, vp3, dh3), dw3-1, map_to_dot_y(lz3.lcl, vp3, dh3); dash=4)
                end
                if _line_on(m, "cl")
                    line!(c3, 0, map_to_dot_y(lz3.cl, vp3, dh3), dw3-1, map_to_dot_y(lz3.cl, vp3, dh3))
                end
                if _line_on(m, "specs")
                    if ch3.usl !== nothing; sy=map_to_dot_y(ch3.usl,vp3,dh3); dashed_line!(c3,0,sy,dw3-1,sy;dash=2); end
                    if ch3.lsl !== nothing; sy=map_to_dot_y(ch3.lsl,vp3,dh3); dashed_line!(c3,0,sy,dw3-1,sy;dash=2); end
                end
                render_canvas(c3, inn3, f)
                # color overlays + markers for ch3 (gated)
                function _d3!(r,v,st,stp=3); yy=data_val_to_cell_row(v,r,vp3); for xx in r.x:right(r); if (xx%stp)==0; set_char!(buf,xx,yy,'-',st); end; end; end
                if _line_on(m, "specs")
                    if ch3.usl!==nothing; _d3!(inn3,ch3.usl,tstyle(:error,bold=true),2); end
                    if ch3.lsl!==nothing; _d3!(inn3,ch3.lsl,tstyle(:error,bold=true),2); end
                end
                if _line_on(m, "sigma3")
                    _d3!(inn3,lz3.ucl,tstyle(:warning,bold=true),4); _d3!(inn3,lz3.lcl,tstyle(:warning,bold=true),4)
                end
                if _line_on(m, "sigma2")
                    _d3!(inn3,lz3.ucl2,tstyle(:secondary),3); _d3!(inn3,lz3.lcl2,tstyle(:secondary),3)
                end
                if _line_on(m, "sigma1")
                    _d3!(inn3,lz3.ucl1,tstyle(:text_dim),2); _d3!(inn3,lz3.lcl1,tstyle(:text_dim),2)
                end
                if _line_on(m, "cl")
                    cly3 = data_val_to_cell_row(lz3.cl, inn3, vp3); for xx in inn3.x:right(inn3); set_char!(buf,xx,cly3,'─',tstyle(:accent)); end
                end
                draw_series_connectors!(buf, inn3, ch3.data.values, vp3, m)
                for i in vp3.x0:vp3.x1
                    (i<1||i>n3)&&continue
                    dx=data_index_to_cell(i,inn3,vp3); dy=data_val_to_cell_row(ch3.data.values[i],inn3,vp3)
                    st3 = point_status(i, ctx3, ch3)
                    if st3 == :oos
                        sym3 = '✕'; sty3 = tstyle(:error, bold=true)
                    elseif st3 == :ooc
                        sym3 = '◆'; sty3 = tstyle(:accent, bold=true)
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
        # Use the resolved ctx for active (canonical :mr + band) to avoid duplication
        act_ch = current_chart(m)
        act_ctx = resolve_chart_render_context(act_ch; sigma_method=:mr)
        lz = act_ctx.lz
        set_string!(buf, x, y, "n=$n", tstyle(:text)); y += 1
        set_string!(buf, x, y, "cl=$(round(lz.cl;digits=2)) σ=$(round(lz.sigma;digits=2))", tstyle(:text_dim)); y += 1
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
        # Hover first (priority over long line list when side is short)
        if (hi = m.hovered) !== nothing && 1 <= hi <= n
            if y <= bottom(side_inner) - 1
                v = m.data.values[hi]
                ach = current_chart(m)
                actx = resolve_chart_render_context(ach; sigma_method=:mr)
                st = point_status(hi, actx, ach)
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
                    on = get(m.enabled_rules, rid, false)
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
        # dashboard multi hint (lowest priority when cramped)
        if length(m.charts) > 1
            if y <= bottom(side_inner) - 1
                set_string!(buf, x, y, "Charts: $(length(m.charts))", tstyle(:text_dim))
                y += 1
            end
            for (ci, c) in enumerate(m.charts)
                if y > bottom(side_inner) - 1; break; end
                cctx = resolve_chart_render_context(c; sigma_method=:mr)
                set_string!(buf, x, y, " $(ci==m.active ? "▶" : " ") $(c.name[1:min(8,length(c.name))]) cpk=$(_fmt(cctx.cpk))", tstyle(ci==m.active ? :accent : :text_dim))
                y += 1
            end
        end
    else
        set_string!(buf, x, y, "n=0", tstyle(:text))
    end

    # gauges (slice 6)
    gcols = split_layout(Layout(Horizontal, [Fill(), Fill()]), gauge_row)
    if length(gcols) >= 2
        # Current gauge (simplified arc)
        g1 = gcols[1]
        g1i = render(Block(border_style=tstyle(:border)), g1, buf)
        if g1i.width > 4 && g1i.height > 3 && n > 0
            gc = create_canvas(g1i.width, g1i.height; style=tstyle(:primary))
            cx, cy = g1i.width ÷ 2, g1i.height - 1
            r = min(g1i.width, g1i.height) ÷ 2 - 1
            arc!(gc, cx, cy, r, 0.0, 180.0)
            lastv = m.data.values[end]
            lo = m.lsl !== nothing ? m.lsl : lz.lcl
            hi = m.usl !== nothing ? m.usl : lz.ucl
            norm = clamp((lastv - lo) / (hi - lo + 1e-9), 0.0, 1.0)
            ang = deg2rad(180 - norm * 180)
            nx = round(Int, cx + r * 0.8 * cos(ang))
            ny = round(Int, cy - r * 0.8 * sin(ang))
            line!(gc, cx, cy, nx, ny)
            set_point!(gc, cx, cy)
            render_canvas(gc, g1i, f)
        end
        set_string!(buf, g1.x + 1, g1.y, "Current", tstyle(:text_dim))

        # Cpk gauge
        g2 = gcols[2]
        g2i = render(Block(border_style=tstyle(:border)), g2, buf)
        cr = compute_capability(m.data.values, m.data.cl, m.data.sigma; lsl=m.lsl, usl=m.usl)
        if g2i.width > 4 && g2i.height > 3
            set_string!(buf, g2i.x + 1, g2i.y, cr.cpk === nothing ? "Cpk=—" : "Cpk=$(_fmt(cr.cpk))", tstyle(:text_dim))
        end
    end

    # Make editing state obvious in bottom info (addresses "press u, nothing changes on screen")
    left = if m.editing !== nothing
        " EDITING $(uppercase(string(m.editing))): [$(m.edit_buf)]  (Enter=apply  Esc=cancel  q=quit) "
    else
        " paused=$(m.paused) last=$(m.last_event) mode=$(m.view_mode) "
    end
    render(StatusBar(left=[Span(left, tstyle(:text_dim))], right=[Span("[p g r c v o u t l s] [h k []] [q]", tstyle(:text_dim))]), footer, buf)
end

# small helper for fmt
function _fmt(x)
    if x === nothing
        return "—"
    end
    x < 1 ? string(round(x; digits=3)) : string(round(x; digits=2))
end

# ── Dedicated Help page (adapted from HTML quickstart + WECO defs + workflow) ──
function _render_help_page!(buf, area, m)
    # simple full area text page
    set_string!(buf, area.x+1, area.y, "SPC WORKBENCH — HELP  (Esc/h to close)", tstyle(:title, bold=true))
    y = area.y + 2
    lines = [
        "QUICK START (TUI):",
        "  p/P     toggle pause / live append",
        "  g/G     toggle live append on active chart (live on/off)",
        "  r/R/z/Z reset viewport to full data",
        "  c/C     open/close WECO rule config (1-8 toggle; Tab→Lines→Visual)",
        "  v/V     open chart-line visibility config (CL/±σ/specs)",
        "  o/O     open Visual Preferences (solid series line, …)",
        "  u/U t/T l/L  edit USL / Target / LSL (enter to set, esc cancel)",
        "  s/S     clear all spec limits",
        "  1..8    toggle WECO rule directly (or 1-5 line keys in Lines tab)",
        "  ← →     pan viewport",
        "  wheel / scroll mouse : zoom around point",
        "  drag LMB : pan; click release : select (thick ┃ )",
        "  hover   : tooltip + crosshair",
        "  [ ]     switch active chart (multi-dashboard)",
        "  h/?     this help",
        "  k       keyboard map page",
        "  q/esc   quit",
        "",
        "RICH VISUALS:",
        "  ◆ = OOC (WECO violation, accent)",
        "  ✕ = OOS (outside USL/LSL when set, red/danger)",
        "  Cpk colored by band: ≥1.67 green, ≥1.33 navy, ≥1.00 amber, <1 red",
        "  Dashed: zone lines (±1/2/3σ), specs (USL/LSL red)",
        "",
        "DASHBOARD: multiple charts visible (switch with []); each has own viewport/specs/rules.",
        "WECO RULES (defaults 1-5 ON): 1=beyond3σ, 2=2of3@2σ, 3=4of5@1σ, 4=8sameCL, 5=6trend, 6=14alt, 7=15in1σ, 8=8out1σ",
        "See original HTML for full defs + workflow. This TUI ports core I-MR + WECO + Cpk fidelity.",
    ]
    for (i, ln) in enumerate(lines)
        if y + i - 1 > bottom(area) - 1; break; end
        set_string!(buf, area.x + 2, y + i - 1, ln, tstyle(:text))
    end
end

# ── Keyboard map page (viewable list of all bindings + mouse) ───────────
function _render_keymap_page!(buf, area, m)
    set_string!(buf, area.x+1, area.y, "KEYBOARD MAP + MOUSE  (Esc/k close) — SPC Workbench", tstyle(:title, bold=true))
    y = area.y + 2
    kbd = [
        "KEYS:",
        "  p/P         Pause/Resume live mode",
        "  g/G         Toggle live_enabled on active chart",
        "  r R z Z     Reset view (full range + auto y)",
        "  c C / v V / o O  Config WECO / Lines / Visual prefs",
        "  u t l / s   Edit USL/Target/LSL / clear specs",
        "  1-8         Toggle WECO-N (or 1-5 in Lines tab)",
        "  [ ] < >     Prev / Next chart (dashboard)",
        "  ← →         Pan left/right",
        "  h ? / k     Help / This keymap",
        "  q Esc       Quit",
        "",
        "MOUSE:",
        "  Move        Hover + vertical follow │ + tooltip",
        "  Left press  Start drag / select",
        "  Left drag   Pan the viewport",
        "  Left release Snap ┃ to nearest point + select",
        "  Wheel up    Zoom in (around cursor)",
        "  Wheel down  Zoom out",
        "",
        "Config: Tab WECO↔Lines; ↑↓/digits/space; Esc/c/v close. Lines ●=draw on chart.",
    ]
    for (i, ln) in enumerate(kbd)
        if y + i - 1 > bottom(area); break; end
        set_string!(buf, area.x + 2, y + i - 1, ln, tstyle(i==1 || startswith(ln,"MOUSE") ? :accent : :text))
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
    # Optional fields from library/prompt PR (PR2b+); skip if not present yet
    if hasfield(typeof(m), :prompt_kind) && getfield(m, :prompt_kind) !== nothing
        return false
    end
    if hasfield(typeof(m), :pending_delete) && getfield(m, :pending_delete) === true
        return false
    end
    m.view_mode in (:help, :keymap, :library, :builder) && return false
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
