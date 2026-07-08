using Test
using Supposition, Supposition.Data
using Random
using Statistics: mean, std

# Pure logic: direct include of the workbench (no Tachikoma dep, per slice 1)
include("../src/spc_workbench.jl")

@testset "SPC Workbench (pure WECO + stats + generator; no UI/Tachikoma)" begin

    @testset "Structs and defaults" begin
        @test WECOViolation <: Any
        @test DEFAULT_WECO_RULES["WECO-1"] == true
        @test DEFAULT_WECO_RULES["WECO-6"] == false
        d = WorkbenchData(values=[1.0], cl=1.0, sigma=0.1)
        @test d.values[1] == 1.0
    end

    @testset "weco_detect guards (empty, zero sigma)" begin
        @test isempty(weco_detect(Float64[], 0.0, 1.0))
        @test isempty(weco_detect([10.0, 20.0], 15.0, 0.0))
        @test isempty(weco_detect([1.0], 0.0, 0.0))
    end

    @testset "WECO-1: 1 point beyond 3σ (exact violations)" begin
        cl, s = 0.0, 1.0
        vals = [0.0, 0.0, 3.5, 0.0, -3.1, 0.0]
        v = weco_detect(vals, cl, s; enabled_rules = Dict("WECO-1" => true))
        @test length(v) == 2
        @test v[1].rule == "WECO-1"
        @test v[1].index == 3
        @test occursin("beyond +3σ", v[1].msg)
        @test v[2].index == 5
        @test occursin("beyond −3σ", v[2].msg)

        # with defaults (WECO-1 on)
        vd = weco_detect(vals, cl, s)
        @test any(x -> x.rule == "WECO-1" && x.index == 3, vd)

        # inside does not
        vals_in = [0.0, 1.0, 2.9]
        @test isempty(weco_detect(vals_in, cl, s; enabled_rules=Dict("WECO-1"=>true)))
    end

    @testset "WECO-2: 2 of 3 consecutive in zone A, same side (red-first exact)" begin
        cl, s = 0.0, 1.0
        # 2 of 3 beyond +2 : positions 2 and 3
        vals = [0.0, 2.1, 2.3]
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-2"=>true))
        @test length(v) == 1
        @test v[1].rule == "WECO-2"
        @test v[1].index == 3
        @test occursin("zone A", v[1].msg)
        @test occursin("+ 2σ", v[1].msg)

        # below side
        vals_b = [0.0, -2.1, -2.2]
        vb = weco_detect(vals_b, cl, s; enabled_rules=Dict("WECO-2"=>true))
        @test length(vb) == 1 && vb[1].index == 3 && occursin("− 2σ", vb[1].msg)

        # exactly 1 does not trigger
        vals1 = [0.0, 2.1, 1.9]
        @test isempty(weco_detect(vals1, cl, s; enabled_rules=Dict("WECO-2"=>true)))

        # mixed sides (no 2 in same bucket): does not
        valsm = [2.1, -2.1, 0.0]
        @test isempty(weco_detect(valsm, cl, s; enabled_rules=Dict("WECO-2"=>true)))

        # default on
        @test !isempty(weco_detect(vals, cl, s))
    end

    @testset "WECO-3: 4 of 5 in zone B same side (exact)" begin
        cl, s = 0.0, 1.0
        # 4 above +1σ in window of 5
        vals = [0.0, 1.1, 1.1, 1.1, 1.1]
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-3"=>true))
        @test length(v) == 1
        @test v[1].rule == "WECO-3"
        @test v[1].index == 5
        @test occursin("zone B", v[1].msg) && occursin("+ 1σ", v[1].msg)

        # 4 below
        valsb = [0.0, -1.1, -1.1, -1.1, -1.1]
        vb = weco_detect(valsb, cl, s; enabled_rules=Dict("WECO-3"=>true))
        @test length(vb) == 1 && vb[1].index == 5

        # only 3 no
        vals3 = [0.0, 1.1, 1.1, 1.1, 0.5]
        @test isempty(weco_detect(vals3, cl, s; enabled_rules=Dict("WECO-3"=>true)))
    end

    @testset "WECO-4: 8 consecutive same side of CL (exact)" begin
        cl, s = 100.0, 2.0
        vals = [101.0, 102.0, 101.5, 103.0, 100.5, 101.0, 102.5, 101.2]
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-4"=>true))
        @test length(v) == 1
        @test v[1].rule == "WECO-4"
        @test v[1].index == 8
        @test occursin("above CL", v[1].msg)

        # below
        valsb = fill(98.0, 8)
        vb = weco_detect(valsb, cl, s; enabled_rules=Dict("WECO-4"=>true))
        @test vb[1].index == 8 && occursin("below CL", vb[1].msg)

        # mixed breaks
        valsm = [101.0 for _ in 1:7]; push!(valsm, 99.0)
        @test isempty(weco_detect(valsm, cl, s; enabled_rules=Dict("WECO-4"=>true)))
    end

    @testset "WECO-5: 6 consecutive trending (exact, independent of sigma)" begin
        cl, s = 0.0, 10.0  # large sigma to avoid other rules
        vals = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-5"=>true))
        @test length(v) == 1
        @test v[1].rule == "WECO-5"
        @test v[1].index == 6
        @test occursin("trending up", v[1].msg)

        valsd = [5.0,4.0,3.0,2.0,1.0,0.0]
        vd = weco_detect(valsd, cl, s; enabled_rules=Dict("WECO-5"=>true))
        @test vd[1].index == 6 && occursin("trending down", vd[1].msg)

        # non-strict stops
        valsn = [0.0,1.0,2.0,2.0,3.0,4.0]
        @test isempty(weco_detect(valsn, cl, s; enabled_rules=Dict("WECO-5"=>true)))
    end

    @testset "WECO-6: 14 alternating (default OFF, enable to hit)" begin
        cl, s = 0.0, 1.0
        # 14 points alternating
        vals = Float64[]
        for i in 1:14; push!(vals, isodd(i) ? 0.0 : 1.0); end
        # with default (OFF) => no
        @test isempty(weco_detect(vals, cl, s))
        # enable
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-6"=>true))
        @test length(v) == 1
        @test v[1].rule == "WECO-6"
        @test v[1].index == 14
        @test occursin("alternating", v[1].msg)

        # non-alt breaks (repeat)
        vals_bad = copy(vals); vals_bad[5] = 0.0; vals_bad[6]=0.0
        @test isempty(weco_detect(vals_bad, cl, s; enabled_rules=Dict("WECO-6"=>true)))
    end

    @testset "WECO-7: 15 inside 1σ (default OFF)" begin
        cl, s = 0.0, 1.0
        vals = [0.05 for _ in 1:15]  # all inside (deterministic)
        vdef = weco_detect(vals, cl, s)
        @test !any(v -> v.rule == "WECO-7", vdef)  # default OFF for 7 (may trigger others)
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-7"=>true))
        @test length(v) == 1 && v[1].rule == "WECO-7" && v[1].index == 15

        # one escape
        vals[8] = 1.5
        @test isempty(weco_detect(vals, cl, s; enabled_rules=Dict("WECO-7"=>true)))
    end

    @testset "WECO-8: 8 outside 1σ (default OFF)" begin
        cl, s = 0.0, 1.0
        vals = [isodd(i) ? 1.5 : -1.5 for i in 1:8]
        @test isempty(weco_detect(vals, cl, s))
        v = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-8"=>true))
        @test length(v) == 1 && v[1].rule == "WECO-8" && v[1].index == 8

        # one inside breaks
        vals[4] = 0.5
        @test isempty(weco_detect(vals, cl, s; enabled_rules=Dict("WECO-8"=>true)))
    end

    @testset "Rule enable/disable and combined violations" begin
        cl, s = 0.0, 1.0
        vals = [3.5, 2.2, 2.1]  # W1 at1 + W2 at3
        vboth = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-1"=>true, "WECO-2"=>true))
        @test any(x->x.rule=="WECO-1" && x.index==1, vboth)
        @test any(x->x.rule=="WECO-2" && x.index==3, vboth)

        v1only = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-1"=>true, "WECO-2"=>false))
        @test length(v1only) == 1 && v1only[1].rule == "WECO-1"
    end

    @testset "compute_limits_and_zones" begin
        lz = compute_limits_and_zones([1.0, 2.0, 3.0])
        @test lz.cl ≈ 2.0 atol=1e-12
        @test lz.sigma > 0
        @test lz.ucl ≈ 2 + 3*lz.sigma
        @test lz.lcl ≈ 2 - 3*lz.sigma
        @test lz.ucl2 ≈ 2 + 2*lz.sigma
        @test lz.ucl1 ≈ 2 + 1*lz.sigma
        @test lz === compute_limits_and_zones([1,2,3])  # type stable-ish

        lz0 = compute_limits_and_zones(Float64[])
        @test lz0.cl == 0.0 && lz0.sigma == 0.0
    end

    @testset "compute_capability (Cpk)" begin
        cr = compute_capability([0.0, 1.0, 2.0], 1.0, 1.0; usl=4.0, lsl=-2.0)
        @test cr.cpk ≈ 1.0
        @test cr.cpu ≈ 1.0
        @test cr.cpl ≈ 1.0
        @test cr.cpk_sigma == 1.0

        cru = compute_capability([10.0], 10.0, 1.0; usl=13.0)
        @test cru.cpk ≈ 1.0 && cru.cpl === nothing

        cr0 = compute_capability(Float64[], 0.0, 1.0; usl=1)
        @test cr0.cpk === nothing

        crz = compute_capability([1.0], 0.0, 0.0; usl=3)
        @test crz.cpk === nothing
    end

    @testset "generate_spc_workbench_data + richer hints" begin
        d = generate_spc_workbench_data(25; seed=123)
        @test length(d.values) == 25
        @test d.cl isa Float64 && d.sigma > 0
        @test d.meta["seed"] == 123
        @test all(isfinite, d.values)

        d2 = generate_spc_workbench_data(10; seed=7, μ=50.0, σ=3.0, hints=Dict{String,Any}("trigger"=>"WECO-2"))
        @test length(d2.values) == 10
        @test d2.meta["trigger"] == "WECO-2"

        # trigger produces OOC relative to target
        @test d2.values[end] > 50 + 2*3
    end

    @testset "PBT / Supposition: generator + detect robustness" begin
        @check function generator_robust(n = Data.Integers(5, 80))
            d = generate_spc_workbench_data(n; seed=42)
            length(d.values) == n && d.sigma >= 0 && all(isfinite, d.values) && d.cl isa Real
        end

        @check function detect_never_crashes(vs = Data.Vectors(Data.Floats(); max_size=60),
                                             cl = Data.Floats(minimum=-1000.0, maximum=1000.0),
                                             s = Data.Floats(minimum=1e-6, maximum=100.0))
            vsf = collect(Float64, vs)
            try
                _ = weco_detect(vsf, cl, s)
                _ = weco_detect(vsf, cl, s; enabled_rules=Dict(k=>rand(Bool) for k in keys(DEFAULT_WECO_RULES)))
                true
            catch e
                false
            end
        end

        @check function no_viol_if_all_in_3s(n=Data.Integers(3,30))
            # generate inside +/- 2.9s using target, pass explicit cl/s to detect
            rng = MersenneTwister(99)
            cl = 0.0; s = 1.0
            vs = [cl + (rand(rng)-0.5)*5.8 * s for _ in 1:n]
            vi = weco_detect(vs, cl, s; enabled_rules=Dict("WECO-1"=>true))
            isempty(vi)
        end
    end
end
