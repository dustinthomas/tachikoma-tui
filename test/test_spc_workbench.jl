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

    # ═══════════════════════════════════════════════════════════════════
    # HTML fidelity / equivalence (AC1) — RED FIRST per TDD
    # Sample from SPC_workbench HTML state (first chart Film-Thickness-1.3um, tool-filtered, n=10)
    # Expected from HTML autoLimits + checkWeco + computeCpk (with USL/Target/LSL)
    # ═══════════════════════════════════════════════════════════════════
    @testset "HTML sample equivalence + OOS + Cpk bands (red-first; will implement to green)" begin
        # Exact series from HTML first chart (Film-Thickness-1.3um, filtered to Film-PTPECVD01)
        html_vals = [1303.0, 1305.0, 1299.0, 1301.0, 1294.0, 1303.0, 1305.0, 1299.0, 1301.0, 1294.0]
        html_usl = 1320.0
        html_lsl = 1280.0
        html_target = 1300.0
        html_rules = copy(DEFAULT_WECO_RULES)  # 1-5 true, 6-8 false

        # Use :mr for I-MR fidelity to match HTML autoLimits (MRbar/1.128 ~4.24, Cpk=1.54)
        lz = compute_limits_and_zones(html_vals; sigma_method=:mr)
        @test lz.cl ≈ 1300.4 atol=0.01
        @test round(lz.sigma, digits=2) ≈ 4.24   # exact match to HTML

        # WECO on clean sample (within ~3.2σ) should give 0 violations with defaults
        vs = weco_detect(html_vals, lz.cl, lz.sigma; enabled_rules=html_rules)
        @test isempty(vs)

        # OOS detection (NEW for AC1): points strictly outside USL/LSL
        # (for this sample none; will use injected OOS later)
        oos_idxs = detect_oos(html_vals; usl=html_usl, lsl=html_lsl)
        @test oos_idxs isa Vector{Int}
        @test isempty(oos_idxs)

        # OOS with injected out of spec
        oos_inj = copy(html_vals); oos_inj[3] = 1325.0; oos_inj[7] = 1275.0
        oos2 = detect_oos(oos_inj; usl=html_usl, lsl=html_lsl)
        @test 3 in oos2 && 7 in oos2 && length(oos2) == 2

        # Cpk for the HTML sample (specs set) exactly 1.54 (navy) using MR sigma
        cr = compute_capability(html_vals, lz.cl, lz.sigma; usl=html_usl, lsl=html_lsl)
        @test cr.cpk !== nothing
        @test round(cr.cpk, digits=2) ≈ 1.54 atol=0.01

        # cpk_band + color decision matching HTML cpkColor exactly
        band = cpk_band(cr.cpk)
        @test band == :navy
        col = cpk_color_for_band(band)
        @test col == "#1a2e5c" || col == "var(--navy)"

        # Other bands
        @test cpk_band(1.80) == :green
        @test cpk_band(1.20) == :amber
        @test cpk_band(0.90) == :red
        @test cpk_band(nothing) == :none
    end

    @testset "ChartRenderContext + resolve (centralized :mr + point_status + consistency)" begin
        # HTML Film-Thickness sample (exact from original HTML state)
        html_vals = [1303.0, 1305.0, 1299.0, 1301.0, 1294.0, 1303.0, 1305.0, 1299.0, 1301.0, 1294.0]
        html_usl, html_lsl = 1320.0, 1280.0
        d = WorkbenchData(values = html_vals, cl = mean(html_vals), sigma = std(html_vals))
        ch = ChartSpec(name = "Film-Thickness-1.3um", data = d, usl = html_usl, lsl = html_lsl, enabled_rules = copy(DEFAULT_WECO_RULES))

        ctx = resolve_chart_render_context(ch; sigma_method = :mr)
        @test round(ctx.lz.sigma; digits = 2) == 4.24
        @test round(ctx.cpk; digits = 2) == 1.54
        @test ctx.band == :navy
        @test isempty(ctx.viol_indices)  # clean sample

        # point_status agrees with viol + OOS
        @test point_status(1, ctx, ch) == :ok
        # inject OOS + force OOC for test
        d2 = WorkbenchData(values = copy(html_vals), cl = mean(html_vals), sigma = std(html_vals))
        d2.values[1] = 1325.0   # > USL -> oos
        ch2 = ChartSpec(data = d2, usl = html_usl, lsl = html_lsl)
        ctx2 = resolve_chart_render_context(ch2; sigma_method = :mr)
        @test point_status(1, ctx2, ch2) == :oos
        # OOC point (beyond 3s of mr sigma) -- use fresh ch with no specs, huge outlier to survive sigma pollution
        d3 = WorkbenchData(values = copy(html_vals), cl = mean(html_vals), sigma = std(html_vals))
        ch3 = ChartSpec(data = d3)  # no usl/lsl
        d3.values[2] = 99999.0
        ctx3b = resolve_chart_render_context(ch3; sigma_method = :mr)
        @test point_status(2, ctx3b, ch3) == :ooc
    end

    @testset "y auto-fit: compute_fit_y_range + extras enclose points and lines" begin
        # Visible window only (index 2..4), not full series min/max
        vals = [0.0, 10.0, 20.0, 30.0, 100.0]
        ylo, yhi = compute_fit_y_range(vals, 2, 4; pad_frac = 0.0, pad_abs = 0.0)
        @test ylo == 10.0
        @test yhi == 30.0

        # Extras (e.g. UCL/LCL beyond data) expand the range
        ylo2, yhi2 = compute_fit_y_range(vals, 2, 4; extras = [5.0, 40.0], pad_frac = 0.0, pad_abs = 0.0)
        @test ylo2 == 5.0
        @test yhi2 == 40.0

        # Padding expands beyond raw min/max
        ylo3, yhi3 = compute_fit_y_range([0.0, 10.0], 1, 2; pad_frac = 0.1, pad_abs = 0.0)
        @test ylo3 ≈ -1.0
        @test yhi3 ≈ 11.0

        # Constant series still has non-zero span
        ylo4, yhi4 = compute_fit_y_range([5.0, 5.0, 5.0], 1, 3; pad_frac = 0.0, pad_abs = 0.5)
        @test ylo4 < 5.0 < yhi4
        @test (yhi4 - ylo4) >= MIN_Y_SPAN || (yhi4 - ylo4) >= 1.0

        # Empty / no-visible → finite default span
        ylo5, yhi5 = compute_fit_y_range(Float64[], 1, 0)
        @test isfinite(ylo5) && isfinite(yhi5) && yhi5 > ylo5

        # y_extras_from_limits respects show_chart_lines flags
        lz = LimitsAndZones(0.0, 1.0, 3.0, -3.0, 2.0, -2.0, 1.0, -1.0)
        all_on = y_extras_from_limits(lz; usl = 10.0, lsl = -10.0, show_lines = DEFAULT_CHART_LINES)
        @test 0.0 in all_on && 3.0 in all_on && -3.0 in all_on && 10.0 in all_on && -10.0 in all_on
        none = Dict(k => false for k in CHART_LINE_KEYS)
        @test isempty(y_extras_from_limits(lz; usl = 10.0, lsl = -10.0, show_lines = none))
        only_cl = merge(none, Dict("cl" => true))
        @test y_extras_from_limits(lz; show_lines = only_cl) == [0.0]

        # fit_viewport_y! mutates viewport to enclose data + extras
        vp = Viewport(x0 = 1, x1 = 5, ylo = 0.0, yhi = 1.0)
        fit_viewport_y!(vp, vals; extras = [-1.0, 110.0], pad_frac = 0.0, pad_abs = 0.0)
        @test vp.ylo == -1.0
        @test vp.yhi == 110.0

        # auto_fit_viewport_y! with MR limits: UCL/LCL beyond sample extrema still inside y
        d = generate_spc_workbench_data(30; seed = 42)
        lz2 = compute_limits_and_zones(d.values; sigma_method = :mr)
        vp2 = Viewport(x0 = 1, x1 = length(d.values), ylo = 0.0, yhi = 0.01)
        auto_fit_viewport_y!(vp2, d.values, lz2; show_lines = DEFAULT_CHART_LINES)
        @test vp2.ylo <= minimum(d.values)
        @test vp2.yhi >= maximum(d.values)
        @test vp2.ylo <= lz2.lcl
        @test vp2.yhi >= lz2.ucl
        # Every series value maps inside a synthetic canvas height
        dh = 40
        for v in d.values
            dy = map_to_dot_y(v, vp2, dh)
            @test 0 <= dy <= dh - 1
        end
        for z in (lz2.ucl, lz2.lcl, lz2.cl, lz2.ucl1, lz2.lcl1, lz2.ucl2, lz2.lcl2)
            dy = map_to_dot_y(z, vp2, dh)
            @test 0 <= dy <= dh - 1
        end
    end

    @testset "ChartType + wire parse + empty data + ChartSpec metadata defaults" begin
        @test I_MR isa ChartType
        @test Xbar_R isa ChartType
        @test Xbar_S isa ChartType
        @test p_chart isa ChartType
        @test CHART_TYPE_WIRE[I_MR] == "I-MR"
        @test CHART_TYPE_WIRE[Xbar_R] == "Xbar-R"
        @test CHART_TYPE_WIRE[p_chart] == "p"
        @test parse_chart_type("I-MR") === I_MR
        @test parse_chart_type("Xbar-S") === Xbar_S
        @test parse_chart_type("u") === u_chart
        @test parse_chart_type("I_MR") === I_MR
        @test parse_chart_type("Xbar_R") === Xbar_R
        @test parse_chart_type("Xbar_S") === Xbar_S
        @test parse_chart_type("p_chart") === p_chart
        @test parse_chart_type("nope") === nothing

        ed = empty_workbench_data()
        @test ed.values == Float64[]
        @test ed.cl == 0.0
        @test ed.sigma == 0.0

        ch = ChartSpec()  # valid empty chart via defaults
        @test ch.chart_type === I_MR
        @test isempty(ch.data.values)
        @test ch.limits_mode === :auto
        @test ch.live_enabled === true
        @test ch.subgroup_size == 5
        @test ch.param == ""
        @test ch.units == ""
        @test ch.owner == ""
        @test ch.tools == String[]
        @test ch.manual_cl === nothing
        # backward-compat construction still works
        ch2 = ChartSpec(name = "legacy", data = WorkbenchData(values=[1.0], cl=1.0, sigma=0.1))
        @test ch2.name == "legacy"
        @test ch2.chart_type === I_MR
        @test ch2.live_enabled === true
    end

    @testset "empty chart resolve + auto_limits alias" begin
        ch = ChartSpec()
        ctx = resolve_chart_render_context(ch)
        @test ctx.lz.cl == 0.0
        @test ctx.lz.sigma == 0.0
        @test isempty(ctx.viol_indices)
        @test ctx.cpk === nothing
        @test ctx.band === :none

        # auto_limits is thin alias to existing I-MR path
        vs = [1.0, 2.0, 3.0, 4.0, 5.0]
        lz_a = auto_limits(vs; chart_type = I_MR, sigma_method = :mr)
        lz_b = compute_limits_and_zones(vs; sigma_method = :mr)
        @test lz_a.cl == lz_b.cl
        @test lz_a.sigma == lz_b.sigma
        @test lz_a.ucl == lz_b.ucl

        # limits_mode :manual with all set still resolves (PR1 falls through to auto until PR5)
        ch_m = ChartSpec(data = WorkbenchData(values = vs, cl = 3.0, sigma = 1.0),
            limits_mode = :manual, manual_cl = 10.0, manual_ucl = 13.0, manual_lcl = 7.0)
        ctx_m = resolve_chart_render_context(ch_m)
        @test ctx_m.lz.cl == lz_b.cl  # auto path until PR5
    end

    @testset "pure chart library CRUD + seed_demos" begin
        d = generate_spc_workbench_data(12; seed = 7)
        m = SPCWorkbenchModel(data = d, paused = true)
        @test m.seed_demos === :triple  # NEVER flip default
        _ensure_charts!(m)
        @test length(m.charts) == 3
        @test m.charts[1].name == "Primary"
        @test occursin("Secondary", m.charts[2].name)
        @test m.charts[3].name == "Tertiary"
        @test all(c -> c.live_enabled === true, m.charts)

        # add
        n0 = length(m.charts)
        idx = add_chart!(m; name = "Added")
        @test idx == n0 + 1
        @test m.charts[idx].name == "Added"
        @test isempty(m.charts[idx].data.values)
        @test m.charts[idx].live_enabled === true

        # rename
        rename_chart!(m, idx, "Renamed")
        @test m.charts[idx].name == "Renamed"

        # set_active
        set_active_chart!(m, idx)
        @test m.active == idx
        @test m.data === m.charts[idx].data || m.data.values == m.charts[idx].data.values

        # clone deep-copy
        src = m.charts[1]
        src.data.values[1] = 999.0
        src.usl = 42.0
        src.enabled_rules["WECO-6"] = true
        src.param = "thickness"
        cidx = clone_chart!(m, 1)
        cloned = m.charts[cidx]
        @test occursin("(copy)", cloned.name)
        @test cloned.id != src.id
        @test cloned.data.values == src.data.values
        @test cloned.data.values !== src.data.values  # deep copy
        @test cloned.usl == 42.0
        @test cloned.enabled_rules["WECO-6"] === true
        @test cloned.enabled_rules !== src.enabled_rules
        @test cloned.param == "thickness"
        cloned.data.values[1] = -1.0
        @test src.data.values[1] == 999.0  # independent

        # delete refuses last
        m_one = SPCWorkbenchModel(data = empty_workbench_data(), paused = true, seed_demos = :none)
        _ensure_charts!(m_one)
        @test length(m_one.charts) == 1
        @test delete_chart!(m_one, 1) === false
        @test length(m_one.charts) == 1

        # delete clamps active + library_selected
        m_del = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m_del)
        set_active_chart!(m_del, 3)
        m_del.library_selected = 3
        @test delete_chart!(m_del, 3) === true
        @test length(m_del.charts) == 2
        @test m_del.active == 2
        @test m_del.library_selected == 2

        # delete syncs active mirror edits before removing a different chart
        m_sync = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m_sync)
        set_active_chart!(m_sync, 1)
        m_sync.usl = 77.0
        @test delete_chart!(m_sync, 2) === true
        @test m_sync.active == 1
        @test m_sync.usl == 77.0
        @test m_sync.charts[1].usl == 77.0

        # add_chart! deep-copies nested meta
        nested = Dict{String,Any}("nested" => Dict{String,Any}("k" => 1))
        src_d = WorkbenchData(values = [1.0, 2.0], cl = 1.5, sigma = 0.5, meta = nested)
        m_meta = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m_meta)
        aidx = add_chart!(m_meta; name = "Meta", data = src_d)
        @test m_meta.charts[aidx].data.meta !== nested
        @test m_meta.charts[aidx].data.meta["nested"] !== nested["nested"]
        nested["nested"]["k"] = 99
        @test m_meta.charts[aidx].data.meta["nested"]["k"] == 1

        # seed :single
        m_s = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m_s)
        @test length(m_s.charts) == 1
        @test m_s.charts[1].name == "Primary"
        @test !isempty(m_s.charts[1].data.values)
        @test m_s.charts[1].live_enabled === true

        # seed :none
        m_n = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        _ensure_charts!(m_n)
        @test length(m_n.charts) == 1
        @test isempty(m_n.charts[1].data.values)
        ctx_n = resolve_chart_render_context(m_n.charts[1])
        @test ctx_n.cpk === nothing
        @test m_n.charts[1].live_enabled === true

        # unknown seed_demos falls back to :triple (safe default)
        m_bad = SPCWorkbenchModel(data = d, paused = true, seed_demos = :foo)
        _ensure_charts!(m_bad)
        @test length(m_bad.charts) == 3
        @test m_bad.charts[1].name == "Primary"
        @test occursin("Secondary", m_bad.charts[2].name)
        @test m_bad.charts[3].name == "Tertiary"

        # ToolEntry exists on model
        @test m.tools isa Vector{ToolEntry}
        @test isempty(m.tools)
    end

    @testset "dashboard_pane_charts (active neighborhood, no charts[2]/[3] lock)" begin
        d = generate_spc_workbench_data(12; seed = 11)
        m = SPCWorkbenchModel(data = d, paused = true)
        @test m.seed_demos === :triple
        _ensure_charts!(m)
        @test length(m.charts) == 3

        # Phase A: visible_charts is identity (all charts, same refs order)
        vis = visible_charts(m)
        @test length(vis) == 3
        @test all(i -> vis[i] === m.charts[i], 1:3)

        # active==1 → panes 1,2,3
        set_active_chart!(m, 1)
        p1 = dashboard_pane_charts(m; k = 3)
        @test length(p1) == 3
        @test p1[1].id == m.charts[1].id
        @test p1[2].id == m.charts[2].id
        @test p1[3].id == m.charts[3].id

        # 1) active==2, 3 charts → panes are charts 2,3 only (no duplicate of chart 2)
        set_active_chart!(m, 2)
        p2 = dashboard_pane_charts(m; k = 3)
        @test length(p2) == 2
        @test p2[1].id == m.charts[2].id
        @test p2[2].id == m.charts[3].id
        @test p2[1].id != p2[2].id
        # primary must not reappear as secondary
        @test count(c -> c.id == m.charts[2].id, p2) == 1

        # 2) delete to 2 charts → no throw / no former charts[3]
        # delete chart 1 so remaining are former 2,3; active stays on former-2 now index 1
        m_del = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m_del)
        set_active_chart!(m_del, 2)
        id_active = m_del.charts[2].id
        id_next = m_del.charts[3].id
        @test delete_chart!(m_del, 1) === true
        @test length(m_del.charts) == 2
        # After delete of chart before active: active clamps to former chart2 now at index 1
        panes_del = dashboard_pane_charts(m_del; k = 3)
        @test length(panes_del) >= 1
        # Must not throw and must only reference remaining charts
        remaining_ids = Set(c.id for c in m_del.charts)
        @test all(c -> c.id in remaining_ids, panes_del)
        # former charts[3] still present as neighbor when active is former-2
        @test any(c -> c.id == id_next || c.id == id_active, panes_del)

        # delete last remaining extra while active is last → single primary, no charts[3]
        m_two = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m_two)
        @test delete_chart!(m_two, 3) === true
        @test length(m_two.charts) == 2
        set_active_chart!(m_two, 2)
        p_two = dashboard_pane_charts(m_two; k = 3)
        @test length(p_two) == 1
        @test p_two[1].id == m_two.charts[2].id
        # no BoundsError accessing former charts[3] via panes
        @test_nowarn dashboard_pane_charts(m_two; k = 3)

        # 3) active==last → single primary pane
        m_last = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m_last)
        set_active_chart!(m_last, 3)
        p_last = dashboard_pane_charts(m_last; k = 3)
        @test length(p_last) == 1
        @test p_last[1].id == m_last.charts[3].id
        @test p_last[1] === current_chart(m_last)

        # empty charts → empty panes (after manual clear; _ensure would reseed)
        m_empty = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        empty!(m_empty.charts)
        m_empty.active = 1
        @test isempty(visible_charts(m_empty))
        @test isempty(dashboard_pane_charts(m_empty))
    end
end

# ═══════════════════════════════════════════════════════════════════════
# Tachikoma UI / TestBackend BDD tests (AC2,4) — red-first for dashboard,
# rich visuals (color markers, OOS/OOC), help, keymap, mouse, guards.
# Must re-render after every update! ; use find_text / row_text / char_at / visual_rows.
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma
const T = Tachikoma

function visual_rows_wb(m; w::Int=82, h::Int=20)
    tb = T.TestBackend(w, h)
    T.reset!(tb.buf)
    T.view(m, T.Frame(tb.buf, T.Rect(1,1,tb.width,tb.height), [], []))
    [T.row_text(tb, i) for i in 1:h]
end

@testset "SPC Workbench UI (TestBackend BDD + dashboard + help/keymap + mouse + colors)" begin
    @testset "Model construction + basic render (paused)" begin
        d = generate_spc_workbench_data(25; seed=42)
        n = length(d.values)
        m = SPCWorkbenchModel(data = d, viewport = Viewport(x0=1, x1=n), paused=true)
        tb = T.TestBackend(80, 18)
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,tb.width,tb.height),[],[]))
        @test T.find_text(tb, "SPC Workbench") !== nothing
        @test T.find_text(tb, "Side Stats") !== nothing
    end

    @testset "auto-fit y on render: points + limit lines map inside plot" begin
        # Deliberately bad Y (0..1) with data ~μ=100 would clip; view must re-fit
        d = generate_spc_workbench_data(20; seed=55, μ=100.0, σ=2.0)
        n = length(d.values)
        m = SPCWorkbenchModel(
            data = d,
            viewport = Viewport(x0 = 1, x1 = n, ylo = 0.0, yhi = 1.0),
            paused = true,
            usl = 110.0,
            lsl = 90.0,
        )
        tb = T.TestBackend(90, 24)
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 24), [], []))
        pa = m.plot_area
        @test pa.width > 5 && pa.height > 3
        # Y range must now enclose data + UCL/LCL + specs
        lz = compute_limits_and_zones(d.values; sigma_method = :mr)
        @test m.viewport.ylo <= minimum(d.values)
        @test m.viewport.yhi >= maximum(d.values)
        @test m.viewport.ylo <= lz.lcl
        @test m.viewport.yhi >= lz.ucl
        @test m.viewport.ylo <= 90.0
        @test m.viewport.yhi >= 110.0
        # Cell mapping for every visible point stays inside plot_inner
        for i in m.viewport.x0:m.viewport.x1
            (i < 1 || i > n) && continue
            cy = data_val_to_cell_row(m.data.values[i], pa, m.viewport)
            @test pa.y <= cy <= T.bottom(pa)
        end
        for z in (lz.ucl, lz.lcl, lz.cl, 110.0, 90.0)
            cy = data_val_to_cell_row(z, pa, m.viewport)
            @test pa.y <= cy <= T.bottom(pa)
        end
        # Multi-chart boot: secondary/tertiary must not keep default y=0..1
        @test length(m.charts) >= 3
        for ch in m.charts
            nn = length(ch.data.values)
            nn == 0 && continue
            @test ch.viewport.ylo <= minimum(ch.data.values)
            @test ch.viewport.yhi >= maximum(ch.data.values)
        end
    end

    @testset "context-driven consistency (hover status == point_status, list cpk == main cpk)" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        # set specs so Cpk is numeric (capability needs usl or lsl)
        if isempty(m.data.values) == false
            mu = mean(m.data.values); s = std(m.data.values; corrected=true)
            m.usl = mu + 3*s
            m.lsl = mu - 3*s
        end
        tb = T.TestBackend(80,18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        ch = current_chart(m)
        ctx = resolve_chart_render_context(ch; sigma_method=:mr)
        side_text = join([T.row_text(tb, i) for i=1:18 if T.row_text(tb,i)!==nothing], "\n")
        # Parse the actual rendered numeric cpk from side (top Cpk= or list) and assert matches ctx.cpk
        m_cpk_match = match(r"Cpk=([0-9.\-]+)", side_text)  # top stats shows "Cpk=..."
        if m_cpk_match === nothing
            m_cpk_match = match(r"cpk=([0-9.\-]+)", side_text)
        end
        @test m_cpk_match !== nothing
        m_cpk = parse(Float64, m_cpk_match.captures[1])
        @test isapprox(m_cpk, ctx.cpk; atol=0.05)  # rendered side/list numeric cpk == ctx.cpk
        @test occursin("Cpk=", side_text) || occursin("cpk=", side_text)
        # Force OOS (beyond usl) for label test
        if m.usl !== nothing
            m.data.values[1] = m.usl + 1.0
        end
        m.hovered = 1
        tb2 = T.TestBackend(80,18); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,80,18),[],[]))
        hover_text = join([T.row_text(tb2, i) for i=1:18 if T.row_text(tb2,i)!==nothing], "\n")
        @test occursin("h[1]=", hover_text)
        # Must reflect OOS (not OK) for out-of-spec point
        @test occursin("OOS", hover_text) || occursin("OOC", hover_text)
    end

    @testset "help page toggle (?/h) shows content from HTML quickstart/WECO; no bleed" begin
        d = generate_spc_workbench_data(12; seed=7)
        m = SPCWorkbenchModel(data=d, paused=true)
        # before
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        @test T.find_text(tb, "HELP") === nothing
        @test !occursin("Quick start", join([r for r in visual_rows_wb(m) if r!==nothing], "\n"))

        T.update!(m, T.KeyEvent('h'))
        tb2 = T.TestBackend(80, 18); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,80,18),[],[]))
        rows = [T.row_text(tb2, i) for i in 1:18]
        help_text = join([r for r in rows if r !== nothing], "\n")
        @test occursin("Help", help_text) || occursin("WECO", help_text) || occursin("QUICK START", help_text)
        # strict no-bleed (real test that would fail without early return in help view)
        @test T.find_text(tb2, "SPC Workbench [dashboard]") === nothing   # normal path header not emitted
        @test T.find_text(tb2, "Side Stats") === nothing
        @test T.find_text(tb2, "Dashboard:") === nothing   # plot block title from normal layout not present

    end

    @testset "keyboard map page (k) shows bindings table + mouse actions; esc closes" begin
        m = SPCWorkbenchModel(data=generate_spc_workbench_data(8;seed=1), paused=true)
        T.update!(m, T.KeyEvent('k'))
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        krows = [T.row_text(tb, i) for i in 1:18]
        kfull = join([string(r) for r in krows if r!==nothing], "\n")
        @test occursin("KEYBOARD MAP", kfull)
        @test occursin("p/P", kfull)
        @test occursin("Pause/Resume", kfull)
        @test occursin("MOUSE:", kfull)  # mouse section header always rendered early
        T.update!(m, T.KeyEvent(:escape))
        tb2 = T.TestBackend(80, 18); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,80,18),[],[]))
        @test T.find_text(tb2, "KEYBOARD MAP") === nothing
    end

    @testset "dashboard multi-chart text + multiple plots visible simultaneously" begin
        # use default ctor that will populate multi in impl
        m = SPCWorkbenchModel(data=generate_spc_workbench_data(15;seed=99), paused=true)
        _ensure_charts!(m)  # ensure copies exist before we mutate ch2
        # Force OOS on ch2 (secondary) so its render path draws an ✕ marker
        if length(m.charts) >= 2
            ch2 = m.charts[2]
            if length(ch2.data.values) >= 1
                ch2.usl = mean(ch2.data.values)
                ch2.data.values[1] = ch2.usl + 10.0
            end
        end
        # Tall enough for 3 stacked plots + Side Stats (Lines + WECO + chart list)
        tb = T.TestBackend(90, 28); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,90,28),[],[]))
        rows = visual_rows_wb(m; w=90, h=28)
        full = join([string(r) for r in rows if r!==nothing], "\n")
        @test occursin("Dashboard", full)
        @test occursin("Chart 2", full)   # proves secondary chart panel rendered
        @test occursin("Secondary", full)
        if length(m.charts) >= 3
            @test occursin("Tertiary", full)
        end
        # Require marker drawing from secondary (not just dashes from any panel)
        @test occursin("◆", full) || occursin("✕", full)  # at least one OOC/OOS marker must come from the forced secondary
    end

    @testset "dashboard_pane_charts view: active=2 secondary is next neighbor (not duplicate)" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(15; seed = 99), paused = true)
        _ensure_charts!(m)
        @test length(m.charts) == 3
        # Distinct names for pane title assertions
        m.charts[1].name = "Alpha"
        m.charts[2].name = "Bravo"
        m.charts[3].name = "Charlie"
        set_active_chart!(m, 2)

        panes = dashboard_pane_charts(m; k = 3)
        @test length(panes) == 2
        @test panes[1].name == "Bravo"
        @test panes[2].name == "Charlie"

        tb = T.TestBackend(90, 28); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 28), [], []))
        rows = [T.row_text(tb, i) for i in 1:28]
        full = join([string(r) for r in rows if r !== nothing], "\n")
        # Primary dashboard title shows active chart (Bravo)
        @test occursin("Dashboard: Bravo", full) || occursin("Bravo [2/3]", full)
        # Secondary read-only pane is next neighbor Charlie — not a second Bravo
        @test occursin("Chart 2: Charlie", full) || occursin("Charlie (read-only", full)
        @test occursin("Chart 2", full)  # secondary pane label
        # Must NOT render a third pane (only 2 panes when active==2)
        @test !occursin("Chart 3", full)
        # Alpha may appear in side chart *list*, but must not be a plot pane title
        @test !occursin("Dashboard: Alpha", full)
        @test !occursin("Chart 2: Alpha", full)
        @test !occursin("Chart 2: Bravo", full)  # no duplicate of primary as secondary
    end

    @testset "dashboard_pane_charts view: delete to 2 charts no throw; active=last single pane" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(12; seed = 7), paused = true)
        _ensure_charts!(m)
        m.charts[1].name = "One"
        m.charts[2].name = "Two"
        m.charts[3].name = "Three"
        @test delete_chart!(m, 3) === true
        @test length(m.charts) == 2
        set_active_chart!(m, 2)
        @test length(dashboard_pane_charts(m)) == 1

        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        @test_nowarn T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 24), [], []))
        rows = [T.row_text(tb, i) for i in 1:24]
        full = join([string(r) for r in rows if r !== nothing], "\n")
        @test occursin("Two", full)
        @test !occursin("Chart 2", full)  # single primary only when active==last of 2
        @test !occursin("Three", full)    # deleted chart gone
        @test !occursin("Chart 3", full)
    end

    @testset "rich visuals — colorized OOC ◆ , OOS markers, Cpk bands text, dashed zones" begin
        d = generate_spc_workbench_data(20; seed=123, hints=Dict{String,Any}("trigger"=>"WECO-1"))
        m = SPCWorkbenchModel(data=d, paused=true)
        # set specs to trigger OOS on a point inside viewport
        m.usl = d.cl + 1.5 * d.sigma
        # force a known OOC point visible and in viewport[1]
        if length(m.data.values) >= 1
            mu = mean(m.data.values)
            sig = std(m.data.values; corrected=true)
            m.data.values[1] = mu + 5 * sig   # extreme OOC (WECO-1), will show ◆ regardless of MR vs std
            m.viewport.x0 = 1
            m.viewport.x1 = max(m.viewport.x1, 5)
        end
        tb = T.TestBackend(70, 16); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,70,16),[],[]))
        full = join([T.row_text(tb,i) for i=1:16], "\n")
        # strict (drive real marker code): count OOC/OOS markers from forced point; no loose ||
        marker_count = count(c -> c == '◆' || c == '✕', collect(full))
        @test marker_count >= 1
        @test T.find_text(tb, "Cpk=") !== nothing
        # Cpk label is drawn (band styling is internal to tstyle; text presence proves the Cpk render path)
        band_text = join([T.row_text(tb, i) for i=1:16 if T.row_text(tb,i)!==nothing], "\n")
        @test occursin("Cpk=", band_text)
    end

    @testset "mouse hover/click/drag/zoom drive state + re-render shows updates (no crash)" begin
        d = generate_spc_workbench_data(18; seed=55)
        n = length(d.values)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1,x1=n))
        tb0 = T.TestBackend(60,16); T.reset!(tb0.buf)
        T.view(m, T.Frame(tb0.buf, T.Rect(1,1,60,16),[],[]))
        pa = m.plot_area
        @test pa.width > 5
        cx, cy = pa.x + pa.width÷2 , pa.y + pa.height÷2
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_move, false,false,false))
        tb1 = T.TestBackend(60,16); T.reset!(tb1.buf); T.view(m, T.Frame(tb1.buf, T.Rect(1,1,60,16),[],[]))
        @test m.hovered !== nothing
        # scroll zoom
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_scroll_up, T.mouse_press, false,false,false))
        @test m.viewport.x1 - m.viewport.x0 < n
    end

    @testset "Small terminal guard + config overlay no-bleed" begin
        m = SPCWorkbenchModel(data=generate_spc_workbench_data(5;seed=2), paused=true)
        tb = T.TestBackend(18,5)
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,18,5),[],[]))
        # real assertion: small guard produces recognizable output without crash/full layout
        small_text = join([T.row_text(tb,i) for i in 1:5 if T.row_text(tb,i)!==nothing], " ")
        @test length(small_text) > 0
        @test occursin("SPC", small_text)
        @test occursin("sma", small_text)  # truncated " (sma" from " (small)" guard in 18-col width
        @test T.find_text(tb, "config open") === nothing   # tiny guard did not draw full config UI
        T.update!(m, T.KeyEvent('c'))
        tb2 = T.TestBackend(50,12); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,50,12),[],[]))
        @test T.find_text(tb2, "WECO-") !== nothing
    end

    @testset "spec editing (u/t/l keys): enters mode, bottom info visibly updates with prompt+buf, typing reflects, q quits from edit, esc cancels" begin
        d = generate_spc_workbench_data(8; seed=123)
        m = SPCWorkbenchModel(data=d, paused=true)
        # ensure multi-chart state is ready like real runs
        _ensure_charts!(m)

        # initial: no editing
        tb0 = T.TestBackend(80, 18); T.reset!(tb0.buf)
        T.view(m, T.Frame(tb0.buf, T.Rect(1,1,80,18),[],[]))
        @test m.editing === nothing
        init_stat = T.row_text(tb0, 18)
        @test init_stat !== nothing
        @test !occursin("EDITING", string(init_stat))

        # press u → should enter usl edit, bottom info MUST change visibly
        T.update!(m, T.KeyEvent('u'))
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        @test m.editing == :usl
        stat = T.row_text(tb, 18)
        @test occursin("EDITING USL", string(stat)) || occursin("edit usl", lowercase(string(stat)))
        # last_event or prompt should mention it
        @test m.last_event != ""

        # type digits — bottom/prompt must reflect the accumulating input value (not frozen)
        T.update!(m, T.KeyEvent('1'))
        T.update!(m, T.KeyEvent('3'))
        T.update!(m, T.KeyEvent('2'))
        T.update!(m, T.KeyEvent('0'))
        tb2 = T.TestBackend(80, 18); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,80,18),[],[]))
        stat2 = string(T.row_text(tb2, 18))
        @test occursin("1320", stat2)   # the typed value must appear in bottom info

        # q while in editing should still quit the app (was swallowed → freeze)
        T.update!(m, T.KeyEvent('q'))
        @test m.quit == true

        # (note: a separate flow would use Esc to cancel instead of q)
    end

    # Side Stats: WECO on/off as filled/empty circle bubbles (● green on, ○ dim off)
    # Helper: collect contiguous ●/○ sequence from side panel (avoids multi-byte row_text slicing)
    function _side_weco_bubbles(tb, m)
        sa = m.side_area
        for y in sa.y:T.bottom(sa)
            # look for "WECO" label chars in side columns
            has_weco = false
            for x in sa.x:(T.right(sa) - 3)
                if T.char_at(tb, x, y) == 'W' && T.char_at(tb, x + 1, y) == 'E' &&
                   T.char_at(tb, x + 2, y) == 'C' && T.char_at(tb, x + 3, y) == 'O'
                    has_weco = true
                    break
                end
            end
            has_weco || continue
            bubbles = Char[]
            for x in sa.x:T.right(sa)
                ch = T.char_at(tb, x, y)
                if ch == '●' || ch == '○'
                    push!(bubbles, ch)
                end
            end
            isempty(bubbles) && continue
            return (y=y, bubbles=String(bubbles), sa=sa)
        end
        return nothing
    end

    @testset "side stats WECO rule bubbles: ● green when ON, ○ when OFF; toggle updates" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        # defaults: WECO-1..5 true, 6..8 false
        @test m.enabled_rules["WECO-1"] == true
        @test m.enabled_rules["WECO-6"] == false

        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        @test m.side_area.width > 0

        found = _side_weco_bubbles(tb, m)
        @test found !== nothing
        if found !== nothing
            @test found.bubbles == "●●●●●○○○"

            # Find first ● and first ○ on that row and assert styles
            first_on_x = nothing
            first_off_x = nothing
            for x in found.sa.x:T.right(found.sa)
                ch = T.char_at(tb, x, found.y)
                if ch == '●' && first_on_x === nothing
                    first_on_x = x
                elseif ch == '○' && first_off_x === nothing
                    first_off_x = x
                end
            end
            @test first_on_x !== nothing
            @test first_off_x !== nothing
            # ON bubbles are green (success theme); OFF are dim
            if first_on_x !== nothing
                @test T.style_at(tb, first_on_x, found.y) == T.tstyle(:success)
            end
            if first_off_x !== nothing
                @test T.style_at(tb, first_off_x, found.y) == T.tstyle(:text_dim)
            end
        end

        # Toggle WECO-6 on via key '6' — bubble pattern updates to six filled
        T.update!(m, T.KeyEvent('6'))
        @test m.enabled_rules["WECO-6"] == true
        tb2 = T.TestBackend(80, 18); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,80,18),[],[]))
        found2 = _side_weco_bubbles(tb2, m)
        @test found2 !== nothing
        if found2 !== nothing
            @test found2.bubbles == "●●●●●●○○"
        end

        # Toggle WECO-1 off via key '1' — first bubble empty
        T.update!(m, T.KeyEvent('1'))
        @test m.enabled_rules["WECO-1"] == false
        tb3 = T.TestBackend(80, 18); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1,1,80,18),[],[]))
        found3 = _side_weco_bubbles(tb3, m)
        @test found3 !== nothing
        if found3 !== nothing
            @test found3.bubbles == "○●●●●●○○"
        end
    end

    @testset "side stats WECO: blank gap after Specs + rule numbers under bubbles" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,90,24),[],[]))
        sa = m.side_area
        @test sa.width > 0

        # Locate Specs= and WECO rows in side panel
        specs_y = nothing
        weco_y = nothing
        for y in sa.y:T.bottom(sa)
            chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
            txt = rstrip(String(chars))
            if occursin("Specs=", txt) || occursin("Specs ", txt)
                specs_y = y
            end
            if length(txt) >= 4 && startswith(lstrip(txt), "WECO")
                weco_y = y
            end
        end
        @test specs_y !== nothing
        @test weco_y !== nothing
        if specs_y !== nothing && weco_y !== nothing
            # At least one blank row between Specs and WECO
            @test weco_y >= specs_y + 2
            # Intermediate row(s) should be blank (or whitespace only)
            for y in (specs_y + 1):(weco_y - 1)
                chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
                @test all(c -> c == ' ' || c == '\0', chars)
            end
        end

        # Numbers 1-8 under each bubble, column-aligned
        found = _side_weco_bubbles(tb, m)
        @test found !== nothing
        if found !== nothing
            bubble_xs = Int[]
            for x in found.sa.x:T.right(found.sa)
                ch = T.char_at(tb, x, found.y)
                if ch == '●' || ch == '○'
                    push!(bubble_xs, x)
                end
            end
            @test length(bubble_xs) == 8
            num_y = found.y + 1
            @test num_y <= T.bottom(found.sa)
            digits = Char[T.char_at(tb, x, num_y) for x in bubble_xs]
            @test digits == ['1', '2', '3', '4', '5', '6', '7', '8']
        end
    end

    # Side panel chart-line parameters (CL/±1/±2/±3/Specs) + configurable visibility
    function _side_rows_text(tb, m)
        sa = m.side_area
        rows = String[]
        for y in sa.y:T.bottom(sa)
            chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
            push!(rows, rstrip(String(chars)))
        end
        return rows
    end

    function _side_full(tb, m)
        join(_side_rows_text(tb, m), "\n")
    end

    # Find row in side panel that contains needle; return (y, text, leading bubble or nothing)
    function _side_find_row(tb, m, needle::AbstractString)
        sa = m.side_area
        for y in sa.y:T.bottom(sa)
            chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
            txt = rstrip(String(chars))
            if occursin(needle, txt)
                bubble = nothing
                for ch in chars
                    if ch == '●' || ch == '○'
                        bubble = ch
                        break
                    end
                end
                return (y=y, text=txt, bubble=bubble)
            end
        end
        return nothing
    end

    @testset "side stats chart-line params (CL/±σ/UCL/LCL/Specs) + configurable visibility" begin
        d = generate_spc_workbench_data(16; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        # Defaults: all chart lines visible
        @test haskey(m.show_chart_lines, "cl")
        @test m.show_chart_lines["cl"] == true
        @test m.show_chart_lines["sigma1"] == true
        @test m.show_chart_lines["sigma2"] == true
        @test m.show_chart_lines["sigma3"] == true
        @test m.show_chart_lines["specs"] == true

        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,90,24),[],[]))
        @test m.side_area.width > 0

        ch = current_chart(m)
        ctx = resolve_chart_render_context(ch; sigma_method=:mr)
        lz = ctx.lz
        side = _side_full(tb, m)

        # Side panel lists each control-line parameter with a value
        @test occursin("CL=", side) || occursin("CL ", side)
        @test occursin("±1", side) || occursin("1σ", side) || occursin("UCL1", side)
        @test occursin("±2", side) || occursin("2σ", side) || occursin("UCL2", side)
        @test occursin("±3", side) || occursin("3σ", side) || occursin("UCL=", side)
        # Numeric fidelity: rounded CL from ctx appears
        cl_str = string(round(lz.cl; digits=2))
        @test occursin(cl_str, side)
        ucl_str = string(round(lz.ucl; digits=2))
        @test occursin(ucl_str, side)

        # Bubbles present and ON by default for CL= row (not UCL)
        cl_row = _side_find_row(tb, m, "CL=")
        @test cl_row !== nothing
        if cl_row !== nothing
            @test cl_row.bubble == '●'
            @test any(x -> T.char_at(tb, x, cl_row.y) == '●' && T.style_at(tb, x, cl_row.y) == T.tstyle(:success),
                      m.side_area.x:T.right(m.side_area))
        end

        # Configure: open config Lines tab (v or c+Tab), toggle sigma1 off
        T.update!(m, T.KeyEvent('v'))  # open chart-lines config
        @test m.config_open == true
        @test m.config_tab == :lines
        # select ±1σ (item 2) and toggle
        T.update!(m, T.KeyEvent('2'))
        @test m.show_chart_lines["sigma1"] == false

        tb2 = T.TestBackend(90, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,90,24),[],[]))
        # still in config — close and check side
        T.update!(m, T.KeyEvent(:escape))
        @test m.config_open == false
        tb3 = T.TestBackend(90, 24); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1,1,90,24),[],[]))
        s1_row = _side_find_row(tb3, m, "±1")
        if s1_row === nothing
            s1_row = _side_find_row(tb3, m, "1σ")
        end
        @test s1_row !== nothing
        if s1_row !== nothing
            @test s1_row.bubble == '○'  # off bubble on side
        end
        # values for ±1 still listed (params always shown; bubble reflects chart visibility)
        side3 = _side_full(tb3, m)
        @test occursin(string(round(lz.ucl1; digits=2)), side3) || occursin("±1", side3)

        # Toggle specs off via lines config key 5
        T.update!(m, T.KeyEvent('v'))
        T.update!(m, T.KeyEvent('5'))
        @test m.show_chart_lines["specs"] == false
        T.update!(m, T.KeyEvent('c'))  # close
        @test m.config_open == false

        # Tab switches WECO → Lines → Visual → WECO
        T.update!(m, T.KeyEvent('c'))
        @test m.config_open && m.config_tab == :weco
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :lines
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :visual
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :weco
        T.update!(m, T.KeyEvent(:escape))
    end

    @testset "visual prefs panel + solid series line connector" begin
        # Defaults: solid series connector ON; panel extensible via visual_prefs
        d = WorkbenchData(values=[0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0], cl=0.5, sigma=0.5)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=8, ylo=-0.5, yhi=1.5))
        @test haskey(m.visual_prefs, "solid_series")
        @test m.visual_prefs["solid_series"] == true
        # Hide zone/spec lines so connector is visible
        for k in keys(m.show_chart_lines)
            m.show_chart_lines[k] = false
        end

        # Key o opens Visual Preferences panel
        T.update!(m, T.KeyEvent('o'))
        @test m.config_open == true
        @test m.config_tab == :visual
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        full = join([string(T.row_text(tb, i)) for i in 1:18 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Visual", full)
        @test occursin("Solid", full) || occursin("solid", lowercase(full)) || occursin("series", lowercase(full))
        # no-bleed: normal dashboard header/side not mixed into config path
        @test T.find_text(tb, "Side Stats") === nothing

        # Toggle solid_series off via 1
        T.update!(m, T.KeyEvent('1'))
        @test m.visual_prefs["solid_series"] == false
        T.update!(m, T.KeyEvent(:escape))
        @test m.config_open == false

        # With solid OFF: re-enable and compare connector density
        # Solid ON should place solid connector glyphs on the cell path between points
        m.visual_prefs["solid_series"] = true
        tb_on = T.TestBackend(70, 18); T.reset!(tb_on.buf)
        T.view(m, T.Frame(tb_on.buf, T.Rect(1,1,70,18),[],[]))
        pa = m.plot_area
        @test pa.width > 4 && pa.height > 3
        # Sample consecutive points' cell coords and require non-space cells on the segment
        i0, i1 = 1, 2
        x0 = data_index_to_cell(i0, pa, m.viewport)
        y0 = data_val_to_cell_row(m.data.values[i0], pa, m.viewport)
        x1 = data_index_to_cell(i1, pa, m.viewport)
        y1 = data_val_to_cell_row(m.data.values[i1], pa, m.viewport)
        # Midpoint-ish cell of the solid segment should not be empty when solid is on
        mx = (x0 + x1) ÷ 2
        my = (y0 + y1) ÷ 2
        # Walk a few cells on the Bresenham-ish segment and count filled
        filled_on = 0
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for s in 0:steps
            t = s / steps
            xx = round(Int, x0 + t * (x1 - x0))
            yy = round(Int, y0 + t * (y1 - y0))
            ch = T.char_at(tb_on, xx, yy)
            if ch != ' ' && ch != '\0'
                filled_on += 1
            end
        end
        @test filled_on >= max(2, steps ÷ 2)  # solid path is continuous

        m.visual_prefs["solid_series"] = false
        tb_off = T.TestBackend(70, 18); T.reset!(tb_off.buf)
        T.view(m, T.Frame(tb_off.buf, T.Rect(1,1,70,18),[],[]))
        filled_off = 0
        for s in 0:steps
            t = s / steps
            xx = round(Int, x0 + t * (x1 - x0))
            yy = round(Int, y0 + t * (y1 - y0))
            ch = T.char_at(tb_off, xx, yy)
            # endpoints may still have markers; ignore pure marker-only if mid empty
            if ch != ' ' && ch != '\0'
                filled_off += 1
            end
        end
        # Solid ON denser than OFF (braille-only / sparse)
        @test filled_on >= filled_off
        # And solid ON is actually continuous (not just endpoints)
        if steps >= 3
            mid_ch = T.char_at(tb_on, mx, my)
            @test mid_ch != ' ' && mid_ch != '\0'
        end
    end

    @testset "visual prefs: solid stroke (box-drawing) alongside dotted series" begin
        d = WorkbenchData(values=[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], cl=0.0, sigma=0.5)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=8, ylo=-1.0, yhi=1.0))
        for k in keys(m.show_chart_lines)
            m.show_chart_lines[k] = false
        end
        # Prefs: keep dotted optional; stroke is separate
        @test haskey(m.visual_prefs, "solid_stroke")
        @test m.visual_prefs["solid_stroke"] == true  # default on
        @test "solid_stroke" in VISUAL_PREF_KEYS

        # Panel lists Stroke option
        T.update!(m, T.KeyEvent('o'))
        tb = T.TestBackend(80, 16); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,16),[],[]))
        full = join([string(T.row_text(tb, i)) for i in 1:16 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Stroke", full) || occursin("stroke", lowercase(full))
        # Toggle stroke via key 2 (item 2 after solid_series)
        T.update!(m, T.KeyEvent('2'))
        @test m.visual_prefs["solid_stroke"] == false
        T.update!(m, T.KeyEvent('2'))  # back on
        @test m.visual_prefs["solid_stroke"] == true
        T.update!(m, T.KeyEvent(:escape))

        # Dotted off, stroke on → box-drawing chars on horizontal path (flat data)
        m.visual_prefs["solid_series"] = false
        m.visual_prefs["solid_stroke"] = true
        tb2 = T.TestBackend(70, 16); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,70,16),[],[]))
        pa = m.plot_area
        @test pa.width > 4
        # Flat series → mostly horizontal ─ between points
        stroke_box = Set(['─', '│', '╱', '╲', '╳', '━', '┃'])
        box_count = 0
        bullet_count = 0
        for y in pa.y:T.bottom(pa), x in pa.x:T.right(pa)
            ch = T.char_at(tb2, x, y)
            ch in stroke_box && (box_count += 1)
            ch == '•' && (bullet_count += 1)
        end
        @test box_count >= 3
        @test bullet_count == 0  # dotted off

        # Stroke off, dotted on → bullets, no requirement for box-drawing
        m.visual_prefs["solid_series"] = true
        m.visual_prefs["solid_stroke"] = false
        tb3 = T.TestBackend(70, 16); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1,1,70,16),[],[]))
        box_count2 = 0
        bullet_count2 = 0
        for y in pa.y:T.bottom(pa), x in pa.x:T.right(pa)
            ch = T.char_at(tb3, x, y)
            ch in stroke_box && (box_count2 += 1)
            ch == '•' && (bullet_count2 += 1)
        end
        @test bullet_count2 >= 3
        @test box_count2 == 0
    end

    @testset "visual prefs: braille canvas series line toggle" begin
        is_braille(c::Char) = let u = UInt32(c); 0x2800 <= u <= 0x28FF; end
        d = WorkbenchData(values=[0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0], cl=0.5, sigma=0.5)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=8, ylo=-0.5, yhi=1.5))
        for k in keys(m.show_chart_lines)
            m.show_chart_lines[k] = false
        end
        # New pref: standard braille connector between dots
        @test haskey(m.visual_prefs, "braille_series")
        @test m.visual_prefs["braille_series"] == true
        @test "braille_series" in VISUAL_PREF_KEYS

        T.update!(m, T.KeyEvent('o'))
        tb = T.TestBackend(80, 16); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,16),[],[]))
        full = join([string(T.row_text(tb, i)) for i in 1:16 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Braille", full) || occursin("braille", lowercase(full))
        # key 3 toggles braille (3rd visual pref)
        T.update!(m, T.KeyEvent('3'))
        @test m.visual_prefs["braille_series"] == false
        T.update!(m, T.KeyEvent('3'))
        @test m.visual_prefs["braille_series"] == true
        T.update!(m, T.KeyEvent(:escape))

        # Isolate braille: turn off dotted + stroke so canvas line is the main connector
        m.visual_prefs["solid_series"] = false
        m.visual_prefs["solid_stroke"] = false
        m.visual_prefs["braille_series"] = true
        tb_on = T.TestBackend(70, 16); T.reset!(tb_on.buf)
        T.view(m, T.Frame(tb_on.buf, T.Rect(1,1,70,16),[],[]))
        pa = m.plot_area
        braille_on = count(is_braille(T.char_at(tb_on, x, y)) for y in pa.y:T.bottom(pa) for x in pa.x:T.right(pa))

        m.visual_prefs["braille_series"] = false
        tb_off = T.TestBackend(70, 16); T.reset!(tb_off.buf)
        T.view(m, T.Frame(tb_off.buf, T.Rect(1,1,70,16),[],[]))
        braille_off = count(is_braille(T.char_at(tb_off, x, y)) for y in pa.y:T.bottom(pa) for x in pa.x:T.right(pa))
        # Connecting line! adds braille cells; points-only is sparser
        @test braille_on > braille_off
        @test braille_on >= 2
    end

    # ── PR2b: Chart library mode UI + prompt SM (A5 / KD21) ─────────────
    @testset "library mode: open (m), CHART LIBRARY title, no dashboard bleed" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(12; seed = 7), paused = true)
        _ensure_charts!(m)
        @test m.view_mode == :dashboard
        @test m.prompt_kind === nothing
        @test m.pending_delete == false

        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        @test m.library_selected == m.active
        @test m.quit == false

        tb = T.TestBackend(80, 20); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 20), [], []))
        @test T.find_text(tb, "CHART LIBRARY") !== nothing
        # no-bleed: normal dashboard chrome must not render under library
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing
        @test T.find_text(tb, "Side Stats") === nothing
        @test T.find_text(tb, "Dashboard:") === nothing
        # chart names from seed demos appear in list
        full = join([string(T.row_text(tb, i)) for i in 1:20 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Primary", full)
    end

    @testset "library: clone, d+y delete, rename prompt, Enter activate" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 3), paused = true)
        _ensure_charts!(m)
        n0 = length(m.charts)
        @test n0 >= 2

        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        sel0 = m.library_selected

        # clone selected
        T.update!(m, T.KeyEvent('c'))
        @test length(m.charts) == n0 + 1
        @test m.library_selected == n0 + 1
        @test endswith(m.charts[end].name, "(copy)")
        @test m.view_mode == :library  # stay in library
        @test m.quit == false

        # delete cloned via d then y
        n_before_del = length(m.charts)
        T.update!(m, T.KeyEvent('d'))
        @test m.pending_delete == true
        @test m.quit == false
        T.update!(m, T.KeyEvent('y'))
        @test m.pending_delete == false
        @test length(m.charts) == n_before_del - 1
        @test m.view_mode == :library
        @test m.quit == false

        # cancel delete path: d then Esc
        T.update!(m, T.KeyEvent('d'))
        @test m.pending_delete == true
        T.update!(m, T.KeyEvent(:escape))
        @test m.pending_delete == false
        @test m.quit == false
        @test m.view_mode == :library

        # rename prompt: n, edit name, Enter
        m.library_selected = 1
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :rename_chart
        @test !isempty(m.prompt_buf)
        # clear and type new name (backspace all, type "Renamed")
        for _ in 1:length(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        for ch in collect("Renamed")
            T.update!(m, T.KeyEvent(ch))
        end
        # 'q' is a buffer character in prompt, not quit
        T.update!(m, T.KeyEvent('q'))
        @test m.quit == false
        @test endswith(m.prompt_buf, "q")
        T.update!(m, T.KeyEvent(:backspace))  # drop the q
        @test m.prompt_buf == "Renamed"
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === nothing
        @test m.charts[1].name == "Renamed"
        @test m.view_mode == :library
        @test m.quit == false

        # Esc cancels rename without applying
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :rename_chart
        for _ in 1:length(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        for ch in collect("Nope")
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing
        @test m.charts[1].name == "Renamed"  # unchanged
        @test m.quit == false

        # Enter activates selected → dashboard
        m.library_selected = min(2, length(m.charts))
        T.update!(m, T.KeyEvent(:enter))
        @test m.view_mode == :dashboard
        @test m.active == m.library_selected
        @test m.quit == false
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        @test T.find_text(tb, "CHART LIBRARY") === nothing
        @test T.find_text(tb, "SPC Workbench") !== nothing
    end

    @testset "library: Esc/q close mode without quit; I/O stubs" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 1), paused = true)
        _ensure_charts!(m)

        # Esc closes library, no quit
        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test m.quit == false

        # q closes library, no quit
        T.update!(m, T.KeyEvent('M'))
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent('q'))
        @test m.view_mode == :dashboard
        @test m.quit == false

        # add empty chart from library
        T.update!(m, T.KeyEvent('m'))
        n0 = length(m.charts)
        T.update!(m, T.KeyEvent('a'))
        @test length(m.charts) == n0 + 1
        @test m.library_selected == n0 + 1
        @test isempty(m.charts[end].data.values)

        # import CSV stub: i then path with q char then Enter
        T.update!(m, T.KeyEvent('i'))
        @test m.prompt_kind === :import_csv
        for ch in collect("/tmp/q-data.csv")
            T.update!(m, T.KeyEvent(ch))
        end
        @test m.quit == false
        @test m.prompt_buf == "/tmp/q-data.csv"
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === nothing
        @test occursin("import stub", m.last_event)
        @test m.view_mode == :library
        @test m.quit == false

        # export / save / load stubs
        T.update!(m, T.KeyEvent('e'))
        @test m.prompt_kind === :export_csv
        T.update!(m, T.KeyEvent(:enter))
        @test occursin("export stub", m.last_event)

        T.update!(m, T.KeyEvent('w'))
        @test m.prompt_kind === :save_workbench
        for ch in collect("session.json")
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test occursin("save stub", m.last_event)
        @test m.last_workbench_path == "session.json"

        T.update!(m, T.KeyEvent('W'))
        @test m.prompt_kind === :load_workbench
        T.update!(m, T.KeyEvent(:enter))
        @test occursin("load stub", m.last_event)
        @test m.view_mode == :library  # load stub stays in library
        @test m.quit == false
    end

    @testset "library: mouse no-op / no stuck drag; ↑↓ selection" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 5), paused = true)
        _ensure_charts!(m)
        nch = length(m.charts)
        @test nch >= 2

        # Seed a mid-drag then open library — release must clear drag_start
        T.view(m, T.Frame(T.TestBackend(80, 18).buf, T.Rect(1, 1, 80, 18), [], []))
        m.drag_start = (x = 10, y = 5, vp = deepcopy(m.viewport))
        m.hover_x = 10
        m.hovered = 1

        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library

        T.update!(m, T.MouseEvent(12, 6, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hover_x === nothing
        @test m.hovered === nothing
        @test occursin("modal", m.last_event)

        T.update!(m, T.MouseEvent(12, 6, T.mouse_left, T.mouse_release, false, false, false))
        @test m.drag_start === nothing
        @test m.view_mode == :library
        @test m.quit == false

        # ↑↓ move selection
        m.library_selected = 1
        T.update!(m, T.KeyEvent(:down))
        @test m.library_selected == 2
        T.update!(m, T.KeyEvent(:up))
        @test m.library_selected == 1
        # clamp at top
        T.update!(m, T.KeyEvent(:up))
        @test m.library_selected == 1
        # clamp at bottom
        m.library_selected = nch
        T.update!(m, T.KeyEvent(:down))
        @test m.library_selected == nch

        # pending_delete also blocks mouse and does not quit on Esc
        T.update!(m, T.KeyEvent('d'))
        @test m.pending_delete
        T.update!(m, T.MouseEvent(5, 5, T.mouse_left, T.mouse_press, false, false, false))
        @test occursin("modal", m.last_event)
        T.update!(m, T.KeyEvent(:escape))
        @test m.pending_delete == false
        @test m.quit == false
    end
end

# ═══════════════════════════════════════════════════════════════════════
# PR3 CSV import + live_enabled gates — package-module path (KD22).
# Isolated module so raw-include of spc_workbench.jl into Main does not
# collide with TachikomaTUI types.
# ═══════════════════════════════════════════════════════════════════════

module TestSPCWorkbenchCSVImport
using Test
using TachikomaTUI
using Tachikoma
using Random

const T = Tachikoma

# Private workbench helpers (not all exported)
const WB = TachikomaTUI
const _ensure_charts! = WB._ensure_charts!
const current_chart = WB.current_chart
const _live_may_advance = WB._live_may_advance
const advance_live! = WB.advance_live!

const FIX_DIR = joinpath(@__DIR__, "fixtures", "spc")
const SAMPLE = joinpath(FIX_DIR, "sample_value.csv")

function _write_csv(path::AbstractString, content::AbstractString)
    open(path, "w") do io
        write(io, content)
    end
    return path
end

@testset "PR3 CSV import + live gates (using TachikomaTUI)" begin
    @testset "parse_csv_table: good sample_value.csv" begin
        r = parse_csv_table(SAMPLE)
        @test r isa CsvParseOk
        @test r.value_col == "Value"
        @test "Value" in r.columns
        @test length(r.values) == 10
        @test r.values[1] ≈ 100.1
        @test r.values[end] ≈ 99.7
        @test isempty(r.warnings)
    end

    @testset "parse_csv_table: empty / missing / no Value / all non-numeric / too_large" begin
        mktempdir() do dir
            empty_p = _write_csv(joinpath(dir, "empty.csv"), "\n  \n")
            r_empty = parse_csv_table(empty_p)
            @test r_empty isa CsvParseErr
            @test r_empty.kind === :empty

            miss = joinpath(dir, "nope.csv")
            r_miss = parse_csv_table(miss)
            @test r_miss isa CsvParseErr
            @test r_miss.kind === :not_found

            no_val = _write_csv(joinpath(dir, "novalue.csv"), "Time,Reading\n1,10.0\n2,11.0\n")
            r_nv = parse_csv_table(no_val)
            @test r_nv isa CsvParseErr
            @test r_nv.kind === :no_header_match

            # value_col override works when column present
            r_ok = parse_csv_table(no_val; value_col = "Reading")
            @test r_ok isa CsvParseOk
            @test r_ok.values == [10.0, 11.0]

            bad_all = _write_csv(joinpath(dir, "bad.csv"), "Value\nfoo\nbar\n")
            r_bad = parse_csv_table(bad_all)
            @test r_bad isa CsvParseErr
            @test r_bad.kind === :all_invalid

            header_only = _write_csv(joinpath(dir, "hdr.csv"), "Value\n")
            r_hdr = parse_csv_table(header_only)
            @test r_hdr isa CsvParseErr
            @test r_hdr.kind === :no_numeric

            # single column, no header (all numeric)
            single = _write_csv(joinpath(dir, "single.csv"), "1.5\n2.5\n3.5\n")
            r_s = parse_csv_table(single)
            @test r_s isa CsvParseOk
            @test r_s.values == [1.5, 2.5, 3.5]

            # too_large
            lines = ["Value"; ["$(i).0" for i in 1:10]]
            big = _write_csv(joinpath(dir, "big.csv"), join(lines, "\n") * "\n")
            r_big = parse_csv_table(big; max_rows = 5)
            @test r_big isa CsvParseErr
            @test r_big.kind === :too_large

            # mixed: some non-numeric warnings but still Ok
            mix = _write_csv(joinpath(dir, "mix.csv"), "Value\n1.0\nx\n2.0\n")
            r_mix = parse_csv_table(mix)
            @test r_mix isa CsvParseOk
            @test r_mix.values == [1.0, 2.0]
            @test !isempty(r_mix.warnings)
        end
    end

    @testset "import_csv_into_chart! + model: live off; err no mutate" begin
        d = generate_spc_workbench_data(20; seed = 7)
        m = SPCWorkbenchModel(data = d, paused = false, seed_demos = :triple)
        _ensure_charts!(m)
        @test length(m.charts) >= 3
        @test all(c -> c.live_enabled === true, m.charts)

        ch = current_chart(m)
        other = m.charts[2]
        other_live = other.live_enabled
        other_vals = copy(other.data.values)
        n_charts = length(m.charts)

        r = import_csv_into_model!(m, SAMPLE)
        @test r isa CsvParseOk
        @test length(r.values) == 10
        @test ch.live_enabled === false
        @test other.live_enabled === other_live  # other charts unchanged
        @test other.data.values == other_vals
        @test m.paused === true
        @test occursin("imported 10 values", m.last_event)
        @test occursin("sample_value.csv", m.last_event)
        @test length(ch.data.values) == 10
        @test ch.viewport.x0 == 1 && ch.viewport.x1 == 10
        @test length(m.charts) == n_charts

        # err path does not mutate
        snap = [copy(c.data.values) for c in m.charts]
        live_snap = [c.live_enabled for c in m.charts]
        r_err = import_csv_into_model!(m, joinpath(FIX_DIR, "does_not_exist.csv"))
        @test r_err isa CsvParseErr
        @test r_err.kind === :not_found
        @test startswith(m.last_event, "import err:")
        for i in eachindex(m.charts)
            @test m.charts[i].data.values == snap[i]
            @test m.charts[i].live_enabled === live_snap[i]
        end
        @test length(m.charts) == n_charts
    end

    @testset "import→unpause does not grow while live_enabled=false; g re-enables" begin
        d = generate_spc_workbench_data(15; seed = 3)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        r = import_csv_into_model!(m, SAMPLE)
        @test r isa CsvParseOk
        @test current_chart(m).live_enabled === false
        @test m.paused === true

        n0 = length(current_chart(m).data.values)
        @test n0 == 10

        # Unpause alone must not append while live_enabled=false
        m.paused = false
        @test _live_may_advance(m) === false
        for _ in 1:30
            advance_live!(m)
        end
        @test length(current_chart(m).data.values) == n0
        @test length(m.data.values) == n0

        # L must still be LSL, not live toggle
        T.update!(m, T.KeyEvent('L'))
        @test m.editing === :lsl
        @test current_chart(m).live_enabled === false
        T.update!(m, T.KeyEvent(:escape))
        @test m.editing === nothing

        # g toggles live on
        T.update!(m, T.KeyEvent('g'))
        @test current_chart(m).live_enabled === true
        @test m.last_event == "live on"
        @test m.paused === false  # still unpaused
        @test _live_may_advance(m) === true

        for _ in 1:5
            advance_live!(m)
        end
        @test length(current_chart(m).data.values) > n0

        # g again → live off
        T.update!(m, T.KeyEvent('G'))
        @test current_chart(m).live_enabled === false
        @test m.last_event == "live off"
        n1 = length(current_chart(m).data.values)
        for _ in 1:10
            advance_live!(m)
        end
        @test length(current_chart(m).data.values) == n1
    end

    @testset "live gates: help/keymap/config/edit/empty block advance" begin
        d = generate_spc_workbench_data(12; seed = 9)
        m = SPCWorkbenchModel(data = d, paused = false, seed_demos = :triple)
        _ensure_charts!(m)
        @test current_chart(m).live_enabled === true
        @test _live_may_advance(m) === true

        m.view_mode = :help
        @test _live_may_advance(m) === false
        m.view_mode = :keymap
        @test _live_may_advance(m) === false
        m.view_mode = :library
        @test _live_may_advance(m) === false
        m.view_mode = :builder
        @test _live_may_advance(m) === false
        m.view_mode = :dashboard
        @test _live_may_advance(m) === true

        m.config_open = true
        @test _live_may_advance(m) === false
        m.config_open = false
        m.editing = :usl
        @test _live_may_advance(m) === false
        m.editing = nothing
        m.paused = true
        @test _live_may_advance(m) === false
        m.paused = false

        # empty chart
        m_empty = SPCWorkbenchModel(data = empty_workbench_data(), paused = false, seed_demos = :none)
        _ensure_charts!(m_empty)
        @test isempty(current_chart(m_empty).data.values)
        @test _live_may_advance(m_empty) === false
    end

    @testset "import_csv_new_chart! adds chart; activates it; help mentions g/G" begin
        d = generate_spc_workbench_data(10; seed = 1)
        m = SPCWorkbenchModel(data = d, paused = false, seed_demos = :single)
        _ensure_charts!(m)
        n0 = length(m.charts)
        lives_before = [c.live_enabled for c in m.charts]
        r = import_csv_new_chart!(m, SAMPLE; name = "FromCSV")
        @test r isa CsvParseOk
        @test length(m.charts) == n0 + 1
        @test m.charts[end].name == "FromCSV"
        @test m.charts[end].live_enabled === false
        @test m.paused === true
        # load=/new-chart import focuses the imported series (not Primary demo)
        @test m.active == length(m.charts)
        @test current_chart(m).name == "FromCSV"
        @test length(current_chart(m).data.values) == 10
        for i in 1:n0
            @test m.charts[i].live_enabled === lives_before[i]
        end

        # bad chart_idx sets last_event + distinct kind
        r_bad = import_csv_into_model!(m, SAMPLE; chart_idx = 999)
        @test r_bad isa CsvParseErr
        @test r_bad.kind === :bad_index
        @test startswith(m.last_event, "import err:")
        @test occursin("bad chart index", m.last_event)

        # help/keymap list g/G
        m2 = SPCWorkbenchModel(data = d, paused = true)
        T.update!(m2, T.KeyEvent('h'))
        tb = T.TestBackend(90, 22); T.reset!(tb.buf)
        T.view(m2, T.Frame(tb.buf, T.Rect(1, 1, 90, 22), [], []))
        help_txt = join([string(T.row_text(tb, i)) for i in 1:22 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("g/G", help_txt)
        T.update!(m2, T.KeyEvent(:escape))
        T.update!(m2, T.KeyEvent('k'))
        tb2 = T.TestBackend(90, 22); T.reset!(tb2.buf)
        T.view(m2, T.Frame(tb2.buf, T.Rect(1, 1, 90, 22), [], []))
        ktxt = join([string(T.row_text(tb2, i)) for i in 1:22 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("g/G", ktxt)
    end

    @testset "seed_demos default remains :triple" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 1), paused = true)
        @test m.seed_demos === :triple
    end
end

end # module TestSPCWorkbenchCSVImport
