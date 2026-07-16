# Generate PECVD demo CSVs (Film-PTPECVD01). Run from repo root:
#   julia --project=. test/fixtures/spc/pecvd/generate.jl
using Random

const OUTDIR = @__DIR__
const TOOL = "Film-PTPECVD01"

function inject_weco!(vals::Vector{Float64})
    n = length(vals)
    n < 20 && return vals
    cl = sum(vals) / n
    s = sqrt(sum((v - cl)^2 for v in vals) / (n - 1))
    (s <= 0 || !isfinite(s)) && (s = 1.0)
    vals[n - 4] = cl + 4.5 * s
    vals[n - 11] = cl - 4.2 * s
    vals[n - 2] = cl + 2.55 * s
    vals[n - 1] = cl + 2.65 * s
    base = n - 24
    for k in 0:7
        vals[base + k] = cl + 1.2 * s
    end
    return vals
end

function series(μ::Float64, σ::Float64; n::Int = 40, seed::Int)
    rng = MersenneTwister(seed)
    vals = Float64[μ + σ * randn(rng) for _ in 1:n]
    return inject_weco!(vals)
end

function write_param(path::AbstractString, param::AbstractString, μ::Float64, σ::Float64, units::AbstractString; seed::Int)
    vals = series(μ, σ; seed = seed)
    open(path, "w") do io
        println(io, "Timestamp,Tool,Lot,Wafer,Parameter,Units,Value")
        for i in eachindex(vals)
            lot = "L$(1000 + ((i - 1) ÷ 4))"
            wafer = "W$(mod1(i, 8))"
            hh = (i - 1) ÷ 3600
            mm = ((i - 1) % 3600) ÷ 60
            ss = (i - 1) % 60
            ts = "2026-03-15T$(lpad(string(hh), 2, '0')):$(lpad(string(mm), 2, '0')):$(lpad(string(ss), 2, '0'))Z"
            v = round(vals[i]; digits = 4)
            println(io, "$ts,$TOOL,$lot,$wafer,$param,$units,$v")
        end
    end
    μ̂ = sum(vals) / length(vals)
    println("wrote $path  n=$(length(vals))  mean=$(round(μ̂; digits = 4))")
end

params = [
    ("oxide_thickness_1_3um.csv", "Thickness 1.3um", 1300.0, 4.5, "nm", 42),
    ("refractive_index.csv", "Refractive Index", 1.46, 0.008, "", 43),
    ("hsq_thickness.csv", "HSQ Thickness", 600.0, 12.0, "nm", 44),
]

for (file, name, μ, σ, units, seed) in params
    write_param(joinpath(OUTDIR, file), name, μ, σ, units; seed = seed)
end

# Long combined file (all params). Importing this as one chart mixes series —
# use the three split files for the hand tutorial, or :fake_tool for catalog UX.
open(joinpath(OUTDIR, "pecvd_all_params.csv"), "w") do io
    println(io, "Timestamp,Tool,Lot,Wafer,Parameter,Units,Value")
    t = 1
    for (file, name, μ, σ, units, seed) in params
        vals = series(μ, σ; seed = seed)
        for i in eachindex(vals)
            lot = "L$(1000 + ((t - 1) ÷ 4))"
            wafer = "W$(mod1(i, 8))"
            hh = (t - 1) ÷ 3600
            mm = ((t - 1) % 3600) ÷ 60
            ss = (t - 1) % 60
            ts = "2026-03-15T$(lpad(string(hh), 2, '0')):$(lpad(string(mm), 2, '0')):$(lpad(string(ss), 2, '0'))Z"
            v = round(vals[i]; digits = 4)
            println(io, "$ts,$TOOL,$lot,$wafer,$name,$units,$v")
            t += 1
        end
    end
end
println("wrote $(joinpath(OUTDIR, "pecvd_all_params.csv"))")
