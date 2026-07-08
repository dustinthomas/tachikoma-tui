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

@kwdef struct WorkbenchData
    values::Vector{Float64}
    cl::Float64
    sigma::Float64
    meta::Dict{String,Any} = Dict{String,Any}()
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
    compute_limits_and_zones(values; corrected=true)

Returns LimitsAndZones with cl=mean, sigma=std (sample), ±1/2/3σ .
"""
function compute_limits_and_zones(values::AbstractVector{<:Real}; corrected::Bool = true)::LimitsAndZones
    if isempty(values)
        z = 0.0
        return LimitsAndZones(z, z, z, z, z, z, z, z)
    end
    vs = Float64.(values)
    cl = mean(vs)
    sigma = std(vs; corrected = corrected)
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
export DEFAULT_WECO_RULES
