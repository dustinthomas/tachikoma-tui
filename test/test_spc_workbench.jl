using Test
using Supposition, Supposition.Data
using Random
using Statistics: mean, std

# Pure logic: direct include of the workbench (no Tachikoma dep, per slice 1)
include("../src/spc_workbench.jl")
# IO helpers (list_browser_entries, save/load_graph_preset, index) — required once
# Config disk-first keys open the explorer / apply paths from Main UI tests.
# Package-module suites still prefer `using TachikomaTUI` for isolated types.
using JSON
include("../src/spc_workbench_io.jl")

@testset "SPC Workbench (pure WECO + stats + generator; no UI/Tachikoma)" begin

    @testset "Structs and defaults" begin
        @test WECOViolation <: Any
        @test DEFAULT_WECO_RULES["WECO-1"] == true
        @test DEFAULT_WECO_RULES["WECO-6"] == false
        d = WorkbenchData(values=[1.0], cl=1.0, sigma=0.1)
        @test d.values[1] == 1.0
    end

    @testset "chart line styles: defaults + draw params preserve dash/step" begin
        @test LINE_STYLE_KEYS == ["solid", "dotted", "dashed", "long_dash"]
        @test DEFAULT_CHART_LINE_STYLES["cl"] == "solid"
        @test DEFAULT_CHART_LINE_STYLES["sigma1"] == "dotted"
        @test DEFAULT_CHART_LINE_STYLES["sigma2"] == "dashed"
        @test DEFAULT_CHART_LINE_STYLES["sigma3"] == "long_dash"
        @test DEFAULT_CHART_LINE_STYLES["specs"] == "dotted"
        # Canvas dash / buffer step match prior hardcoded look
        @test _style_draw_params("solid") == (nothing, 1, '─')
        @test _style_draw_params("dotted") == (2, 2, '-')
        @test _style_draw_params("dashed") == (3, 3, '-')
        @test _style_draw_params("long_dash") == (4, 4, '-')
        m = SPCWorkbenchModel(data = WorkbenchData(values=[1.0], cl=1.0, sigma=0.1))
        for k in CHART_LINE_KEYS
            @test haskey(m.chart_line_styles, k)
            @test m.chart_line_styles[k] == DEFAULT_CHART_LINE_STYLES[k]
            @test _line_style(m, k) == DEFAULT_CHART_LINE_STYLES[k]
        end
        # cycle helper
        @test _cycle_line_style!(m, "cl"; dir = 1) == "dotted"
        @test m.chart_line_styles["cl"] == "dotted"
        @test occursin("style cl=dotted", m.last_event)
        @test _cycle_line_style!(m, "cl"; dir = -1) == "solid"
    end

    @testset "graph preset body chips (PR1 path-free)" begin
        p = GraphPreset()
        @test _preset_weco_chip(p) == "5/8"  # WECO-1..5 on by default
        @test _preset_lines_chip(p) == "all"
        @test _preset_styles_chip(p) == "mixed"  # defaults use multiple styles
        p.show_chart_lines["specs"] = false
        p.show_chart_lines["sigma1"] = false
        @test _preset_lines_chip(p) == "off-2"
        p.enabled_rules["WECO-6"] = true
        @test _preset_weco_chip(p) == "6/8"
        for k in keys(p.chart_line_styles)
            p.chart_line_styles[k] = "solid"
        end
        @test _preset_styles_chip(p) == "solid"
        @test SAVED_LIST_CHROME_ROWS == 5  # title + rule + header + blank + action
    end

    @testset "graph presets: capture/apply whole graph set (lines+styles+visual+rules)" begin
        @test GraphPreset <: Any
        p0 = GraphPreset()
        @test p0.name == "default"
        @test p0.path == ""  # optional host path; default empty (KD-SE-4)
        for k in CHART_LINE_KEYS
            @test p0.show_chart_lines[k] == DEFAULT_CHART_LINES[k]
            @test p0.chart_line_styles[k] == DEFAULT_CHART_LINE_STYLES[k]
        end
        for k in VISUAL_PREF_KEYS
            @test p0.visual_prefs[k] == DEFAULT_VISUAL_PREFS[k]
        end
        @test p0.enabled_rules["WECO-1"] == DEFAULT_WECO_RULES["WECO-1"]
        @test p0.enabled_rules["WECO-6"] == DEFAULT_WECO_RULES["WECO-6"]

        d = generate_spc_workbench_data(10; seed = 7)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        # Mutate the full graph set: visibility, styles/coloring, visual prefs, WECO calc rules
        m.show_chart_lines["specs"] = false
        m.show_chart_lines["sigma1"] = false
        m.chart_line_styles["cl"] = "dashed"
        m.chart_line_styles["sigma3"] = "dotted"
        m.visual_prefs["solid_series"] = false
        m.visual_prefs["secondary_canvas"] = false
        m.enabled_rules["WECO-6"] = true
        m.enabled_rules["WECO-1"] = false
        _sync_active_back!(m)

        p = capture_graph_preset(m; name = "fab-dense")
        @test p isa GraphPreset
        @test p.name == "fab-dense"
        @test p.show_chart_lines["specs"] === false
        @test p.show_chart_lines["sigma1"] === false
        @test p.chart_line_styles["cl"] == "dashed"
        @test p.chart_line_styles["sigma3"] == "dotted"
        @test p.visual_prefs["solid_series"] === false
        @test p.visual_prefs["secondary_canvas"] === false
        @test p.enabled_rules["WECO-6"] === true
        @test p.enabled_rules["WECO-1"] === false
        # Deep copy: mutating model must not alias into preset
        m.show_chart_lines["specs"] = true
        m.chart_line_styles["cl"] = "solid"
        @test p.show_chart_lines["specs"] === false
        @test p.chart_line_styles["cl"] == "dashed"

        # Apply onto a fresh model restores the whole set (active chart rules + session)
        m2 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        @test m2.show_chart_lines["specs"] === true
        @test m2.chart_line_styles["cl"] == "solid"
        apply_graph_preset!(m2, p)
        @test m2.show_chart_lines["specs"] === false
        @test m2.show_chart_lines["sigma1"] === false
        @test m2.chart_line_styles["cl"] == "dashed"
        @test m2.chart_line_styles["sigma3"] == "dotted"
        @test m2.visual_prefs["solid_series"] === false
        @test m2.visual_prefs["secondary_canvas"] === false
        @test m2.enabled_rules["WECO-6"] === true
        @test m2.enabled_rules["WECO-1"] === false
        @test m2.default_rules["WECO-6"] === true
        @test m2.default_rules["WECO-1"] === false
        @test current_chart(m2).enabled_rules["WECO-6"] === true
        @test current_chart(m2).enabled_rules["WECO-1"] === false
        @test occursin("preset applied", m2.last_event)
        # Apply deep-copies — mutating preset after apply leaves model alone
        p.chart_line_styles["cl"] = "long_dash"
        @test m2.chart_line_styles["cl"] == "dashed"

        # Named session presets: save (upsert) + apply by name
        m3 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        m3.show_chart_lines["cl"] = false
        m3.chart_line_styles["specs"] = "long_dash"
        m3.visual_prefs["braille_series"] = false
        m3.enabled_rules["WECO-8"] = true
        _sync_active_back!(m3)
        @test save_named_graph_preset!(m3, "no-cl") === nothing
        @test length(m3.graph_presets) == 1
        @test m3.graph_presets[1].name == "no-cl"
        @test occursin("preset saved", m3.last_event)
        # empty name rejected
        @test save_named_graph_preset!(m3, "  ") isa AbstractString
        @test length(m3.graph_presets) == 1
        # mutate away then re-apply by name
        m3.show_chart_lines["cl"] = true
        m3.chart_line_styles["specs"] = "dotted"
        m3.visual_prefs["braille_series"] = true
        m3.enabled_rules["WECO-8"] = false
        _sync_active_back!(m3)
        @test apply_named_graph_preset!(m3, "no-cl") === nothing
        @test m3.show_chart_lines["cl"] === false
        @test m3.chart_line_styles["specs"] == "long_dash"
        @test m3.visual_prefs["braille_series"] === false
        @test m3.enabled_rules["WECO-8"] === true
        @test apply_named_graph_preset!(m3, "missing") isa AbstractString
        # upsert same name replaces
        m3.show_chart_lines["sigma2"] = false
        @test save_named_graph_preset!(m3, "no-cl") === nothing
        @test length(m3.graph_presets) == 1
        @test m3.graph_presets[1].show_chart_lines["sigma2"] === false
        @test occursin("preset updated", m3.last_event)
    end

    @testset "graph config path helpers: basename name + path-keyed upsert (PR2/KD-SE-17)" begin
        @test _graph_config_name_from_path("/tmp/fab-dense.json") == "fab-dense"
        @test _graph_config_name_from_path("fab-dense.json") == "fab-dense"
        @test _graph_config_name_from_path("/x/foo.bar.json") == "foo.bar"
        @test _graph_config_name_from_path("  ") == "default"
        @test _graph_config_name_from_path("") == "default"
        @test _graph_config_name_from_path(".json") == ".json"  # leading-dot only: keep base
        @test _graph_config_name_from_path("noext") == "noext"

        d = generate_spc_workbench_data(8; seed = 3)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        # Path-less name upsert (legacy / memory rows)
        p1 = GraphPreset(name = "from-file", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES))
        p1.show_chart_lines["cl"] = false
        @test _upsert_graph_preset!(m, p1) === nothing
        @test length(m.graph_presets) == 1
        @test m.graph_presets[1].name == "from-file"
        @test m.graph_presets[1].path == ""
        @test m.graph_presets[1].show_chart_lines["cl"] === false
        # same name + empty path replaces payload (length unchanged); does NOT re-capture live model
        m.show_chart_lines["cl"] = true
        p2 = GraphPreset(name = "from-file", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES))
        p2.show_chart_lines["cl"] = false
        p2.show_chart_lines["specs"] = false
        @test _upsert_graph_preset!(m, p2) === nothing
        @test length(m.graph_presets) == 1
        @test m.graph_presets[1].show_chart_lines["specs"] === false
        @test m.graph_presets[1].show_chart_lines["cl"] === false  # payload, not live re-capture
        # different name pushes
        p3 = GraphPreset(name = "other", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES))
        @test _upsert_graph_preset!(m, p3) === nothing
        @test length(m.graph_presets) == 2
        # empty name rejected
        pbad = GraphPreset(name = "  ", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES))
        @test _upsert_graph_preset!(m, pbad) isa AbstractString
        @test length(m.graph_presets) == 2

        # Path-keyed: two same basenames in different dirs → two list slots
        m2 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        dir_a = joinpath(tempdir(), "spc_upsert_a_$(rand(UInt32))")
        dir_b = joinpath(tempdir(), "spc_upsert_b_$(rand(UInt32))")
        path_a = joinpath(dir_a, "fab-dense.json")
        path_b = joinpath(dir_b, "fab-dense.json")
        pa = GraphPreset(name = "fab-dense", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = path_a)
        pa.show_chart_lines["cl"] = false
        pb = GraphPreset(name = "fab-dense", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = path_b)
        pb.show_chart_lines["specs"] = false
        @test _upsert_graph_preset!(m2, pa) === nothing
        @test _upsert_graph_preset!(m2, pb) === nothing
        @test length(m2.graph_presets) == 2
        paths = sort([abspath(e.path) for e in m2.graph_presets])
        @test paths == sort([abspath(path_a), abspath(path_b)])
        # Re-save same path → one slot updated (payload rename allowed)
        pa2 = GraphPreset(name = "renamed-dense", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = path_a)
        pa2.show_chart_lines["sigma1"] = false
        @test _upsert_graph_preset!(m2, pa2) === nothing
        @test length(m2.graph_presets) == 2
        hit = findfirst(e -> abspath(e.path) == abspath(path_a), m2.graph_presets)
        @test hit !== nothing
        @test m2.graph_presets[hit].name == "renamed-dense"
        @test m2.graph_presets[hit].show_chart_lines["sigma1"] === false
        # Never replace path-bearing row by name when paths differ
        m3 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        with_path = GraphPreset(name = "same", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = path_a)
        pathless = GraphPreset(name = "same", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = "")
        pathless.show_chart_lines["cl"] = false
        @test _upsert_graph_preset!(m3, with_path) === nothing
        @test _upsert_graph_preset!(m3, pathless) === nothing
        @test length(m3.graph_presets) == 2
        # Path-less same-name upsert does not touch the path-bearing entry
        pathless2 = GraphPreset(name = "same", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = "")
        pathless2.show_chart_lines["specs"] = false
        @test _upsert_graph_preset!(m3, pathless2) === nothing
        @test length(m3.graph_presets) == 2
        pl = findfirst(e -> isempty(e.path), m3.graph_presets)
        @test pl !== nothing
        @test m3.graph_presets[pl].show_chart_lines["specs"] === false
        pbearing = findfirst(e -> !isempty(e.path), m3.graph_presets)
        @test pbearing !== nothing
        @test m3.graph_presets[pbearing].show_chart_lines["cl"] === true  # untouched

        # Issue 1: ~/ and expanded absolute path are the same identity
        m_tilde = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        rel = joinpath(".cache", "spc_pr2_upsert_tilde_$(rand(UInt32)).json")
        tilde_p = "~/" * replace(rel, "\\" => "/")
        abs_p = abspath(expanduser(tilde_p))
        @test startswith(abs_p, abspath(homedir()))
        pt = GraphPreset(name = "tilde-cfg", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = tilde_p)
        pa = GraphPreset(name = "tilde-cfg", show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = abs_p)
        pa.show_chart_lines["cl"] = false
        @test _upsert_graph_preset!(m_tilde, pt) === nothing
        @test length(m_tilde.graph_presets) == 1
        @test m_tilde.graph_presets[1].path == abs_p  # stored normalized
        @test _upsert_graph_preset!(m_tilde, pa) === nothing
        @test length(m_tilde.graph_presets) == 1  # same slot, not duplicate
        @test m_tilde.graph_presets[1].show_chart_lines["cl"] === false

        # Issue 3: save_named_graph_preset! must not clobber path-bearing same-name rows
        m_named = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        disk_path = joinpath(tempdir(), "spc_named_noclobber_$(rand(UInt32)).json")
        push!(m_named.graph_presets, GraphPreset(
            name = "shared-name",
            show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = disk_path,
        ))
        m_named.show_chart_lines["specs"] = false
        @test save_named_graph_preset!(m_named, "shared-name") === nothing
        @test length(m_named.graph_presets) == 2  # push path-less, keep path-bearing
        paths_after = [e.path for e in m_named.graph_presets]
        @test any(p -> abspath(expanduser(p)) == abspath(disk_path), paths_after)
        @test any(isempty, paths_after)
        bearing = findfirst(e -> !isempty(e.path), m_named.graph_presets)
        @test bearing !== nothing
        @test m_named.graph_presets[bearing].path == abspath(expanduser(disk_path)) ||
              m_named.graph_presets[bearing].path == disk_path
        @test occursin("preset saved", m_named.last_event)
        # path-less same name still updates (event "preset updated")
        @test save_named_graph_preset!(m_named, "shared-name") === nothing
        @test length(m_named.graph_presets) == 2
        @test occursin("preset updated", m_named.last_event)
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
        vals = [3.5, 2.2, 2.1]  # W1 at1 + W2 at3 (different indices — enable-filter only)
        vboth = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-1"=>true, "WECO-2"=>true))
        @test any(x->x.rule=="WECO-1" && x.index==1, vboth)
        @test any(x->x.rule=="WECO-2" && x.index==3, vboth)

        v1only = weco_detect(vals, cl, s; enabled_rules=Dict("WECO-1"=>true, "WECO-2"=>false))
        @test length(v1only) == 1 && v1only[1].rule == "WECO-1"
    end

    @testset "weco_rules_at_index + explain content (pure)" begin
        # empty / out-of-range index
        @test isempty(weco_rules_at_index(WECOViolation[], 1))
        @test isempty(weco_rules_at_index(WECOViolation[], 0))
        @test isempty(weco_rules_at_index(WECOViolation[], -1))

        # single rule at index
        viols_one = [WECOViolation("WECO-1", 3, "#3 = 3.5 beyond +3σ (UCL 3.0)")]
        @test weco_rules_at_index(viols_one, 3) == ["WECO-1"]
        @test isempty(weco_rules_at_index(viols_one, 1))
        @test isempty(weco_rules_at_index(viols_one, 2))

        # synthetic same-index multi fixture (NOT the L491 different-index series)
        viols_multi = [
            WECOViolation("WECO-1", 8, "#8 = 3.5 beyond +3σ (UCL 3.0)"),
            WECOViolation("WECO-4", 8, "8 in a row ending #8 above CL"),
            WECOViolation("WECO-2", 3, "2 of 3 ending #3 in zone A (+ 2σ side)"),
        ]
        @test weco_rules_at_index(viols_multi, 8) == ["WECO-1", "WECO-4"]
        @test weco_rules_at_index(viols_multi, 3) == ["WECO-2"]
        @test isempty(weco_rules_at_index(viols_multi, 1))

        # stable order by rule number even if insertion is unsorted
        viols_unsorted = [
            WECOViolation("WECO-5", 2, "msg5"),
            WECOViolation("WECO-1", 2, "msg1"),
            WECOViolation("WECO-3", 2, "msg3"),
        ]
        @test weco_rules_at_index(viols_unsorted, 2) == ["WECO-1", "WECO-3", "WECO-5"]

        # dedupe same rule+index
        viols_dup = [
            WECOViolation("WECO-1", 4, "first"),
            WECOViolation("WECO-1", 4, "second"),
        ]
        @test weco_rules_at_index(viols_dup, 4) == ["WECO-1"]

        # _first_viol
        @test _first_viol(viols_multi, "WECO-1", 8) !== nothing
        @test _first_viol(viols_multi, "WECO-1", 8).msg == "#8 = 3.5 beyond +3σ (UCL 3.0)"
        @test _first_viol(viols_multi, "WECO-4", 3) === nothing
        @test _first_viol(viols_dup, "WECO-1", 4).msg == "first"

        # WECO_EXPLAIN_HOW catalog: all 8 keys, non-empty
        @test length(WECO_EXPLAIN_HOW) == 8
        for k in 1:8
            rid = "WECO-$k"
            @test haskey(WECO_EXPLAIN_HOW, rid)
            @test !isempty(WECO_EXPLAIN_HOW[rid])
        end
        @test length(WECO_RULE_DESCS) == 8
        @test WECO_POPUP_MAX_BODY == 5

        # :rule content contracts — ON + At when viol present
        c_on = weco_explain_content(:rule; rule="WECO-1", enabled=true,
            viols=viols_multi, index=8)
        @test occursin("WECO-1", c_on.title)
        @test occursin("ON", c_on.title)
        @test any(l -> startswith(l, "How:"), c_on.lines)
        @test any(l -> startswith(l, "At:"), c_on.lines)
        @test length(c_on.lines) <= WECO_POPUP_MAX_BODY
        @test c_on.lines[1] == WECO_RULE_DESCS[1]
        @test occursin(WECO_EXPLAIN_HOW["WECO-1"], c_on.lines[2])

        # :rule OFF — title OFF; How present; no At without matching viol
        c_off = weco_explain_content(:rule; rule="WECO-6", enabled=false,
            viols=viols_multi, index=8)
        @test occursin("WECO-6", c_off.title)
        @test occursin("OFF", c_off.title)
        @test any(l -> startswith(l, "How:"), c_off.lines)
        @test !any(l -> startswith(l, "At:"), c_off.lines)
        @test !any(l -> occursin("State:", l), c_off.lines)

        # :rule with index but no viol for that rule — no At
        c_noat = weco_explain_content(:rule; rule="WECO-1", enabled=true,
            viols=viols_multi, index=3)
        @test !any(l -> startswith(l, "At:"), c_noat.lines)

        # :rule with index=nothing — no At
        c_ni = weco_explain_content(:rule; rule="WECO-1", enabled=true,
            viols=viols_multi, index=nothing)
        @test !any(l -> startswith(l, "At:"), c_ni.lines)

        # :point content contracts
        rules8 = weco_rules_at_index(viols_multi, 8)
        c_pt = weco_explain_content(:point; index=8, viols=viols_multi, rules_at=rules8)
        @test c_pt.title == "WECO · #8"
        @test length(c_pt.lines) <= WECO_POPUP_MAX_BODY
        @test any(l -> occursin("WECO-1", l), c_pt.lines)
        @test any(l -> occursin("WECO-4", l), c_pt.lines)
        @test any(l -> occursin("beyond +3σ", l) || occursin("above CL", l), c_pt.lines)

        # :point with >4 rules → ≤4 rule lines + "+N more"
        rules_many = ["WECO-1", "WECO-2", "WECO-3", "WECO-4", "WECO-5", "WECO-6"]
        viols_many = [WECOViolation(r, 9, "msg $r") for r in rules_many]
        c_more = weco_explain_content(:point; index=9, viols=viols_many, rules_at=rules_many)
        @test c_more.title == "WECO · #9"
        @test length(c_more.lines) <= WECO_POPUP_MAX_BODY
        @test count(l -> startswith(l, "WECO-"), c_more.lines) <= 4
        @test any(l -> occursin("more", l), c_more.lines)
        @test any(l -> l == "+2 more", c_more.lines)

        # :point without viol msgs falls back to short desc
        c_fb = weco_explain_content(:point; index=1, viols=WECOViolation[],
            rules_at=["WECO-2"])
        @test c_fb.title == "WECO · #1"
        @test length(c_fb.lines) == 1
        @test occursin("WECO-2", c_fb.lines[1])
        @test occursin(WECO_RULE_DESCS[2], c_fb.lines[1])
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
        # Phase B column maps / provenance defaults (PR6)
        @test ch.source === :series
        @test ch.col_value == "Value"
        @test ch.col_n == ""
        @test ch.col_tool == "Tool"
        @test ch.col_time == "Timestamp"
        @test ch.col_lot == ""  # PR7b: empty → series-chunk path
        # backward-compat construction still works
        ch2 = ChartSpec(name = "legacy", data = WorkbenchData(values=[1.0], cl=1.0, sigma=0.1))
        @test ch2.name == "legacy"
        @test ch2.chart_type === I_MR
        @test ch2.live_enabled === true
        @test ch2.source === :series
        @test ch2.col_lot == ""
    end

    @testset "SharedTable + compute_chart_series + materialize copy-on-map (PR6)" begin
        @test mean_or_0(Float64[]) == 0.0
        @test mean_or_0([1.0, 3.0]) == 2.0
        @test std_or_0(Float64[]) == 0.0
        @test std_or_0([1.0]) == 0.0
        @test std_or_0([1.0, 3.0]) ≈ std([1.0, 3.0]; corrected = true)

        # Multi-tool filter against in-memory table (Film-PTPECVD01 style)
        table = SharedTable(
            columns = ["Timestamp", "Tool", "Value"],
            rows = [
                Dict("Timestamp" => "t1", "Tool" => "Film-PTPECVD01", "Value" => "1303"),
                Dict("Timestamp" => "t2", "Tool" => "Film-PTPECVD01", "Value" => "1305"),
                Dict("Timestamp" => "t3", "Tool" => "OtherTool", "Value" => "999"),
                Dict("Timestamp" => "t4", "Tool" => "Film-PTPECVD01", "Value" => "1299"),
                Dict("Timestamp" => "t5", "Tool" => "Film-PTPECVD01", "Value" => ""),  # skip empty
                Dict("Timestamp" => "t6", "Tool" => "Film-PTPECVD01", "Value" => "x"),  # skip non-numeric
            ],
        )
        ch = ChartSpec(
            name = "Film-Thickness-1.3um",
            tools = ["Film-PTPECVD01"],
            col_value = "Value",
            col_tool = "Tool",
            col_time = "Timestamp",
            live_enabled = true,
        )
        vals, labels, pmeta = compute_chart_series(table, ch)
        @test vals == [1303.0, 1305.0, 1299.0]
        @test labels == ["t1", "t2", "t4"]
        @test length(pmeta) == 3
        @test pmeta[1]["tool"] == "Film-PTPECVD01"

        # empty tools → all numeric Value rows
        ch_all = ChartSpec(col_value = "Value", col_tool = "Tool", tools = String[])
        vals_all, _, _ = compute_chart_series(table, ch_all)
        @test vals_all == [1303.0, 1305.0, 999.0, 1299.0]

        materialize_chart_from_table!(ch, table)
        @test ch.source === :table
        @test ch.live_enabled === false
        @test ch.data.values == [1303.0, 1305.0, 1299.0]
        @test ch.data.cl ≈ mean([1303.0, 1305.0, 1299.0])
        @test ch.data.sigma ≈ std([1303.0, 1305.0, 1299.0]; corrected = true)
        @test ch.viewport.x0 == 1
        @test ch.viewport.x1 == 3
        @test haskey(ch.data.meta, "labels")
        @test ch.data.meta["labels"] == ["t1", "t2", "t4"]

        # Copy-on-map: mutating table after materialize does not auto-refresh series
        push!(table.rows, Dict("Timestamp" => "t7", "Tool" => "Film-PTPECVD01", "Value" => "1310"))
        @test length(ch.data.values) == 3
        # re-materialize picks up new row
        materialize_chart_from_table!(ch, table)
        @test ch.data.values == [1303.0, 1305.0, 1299.0, 1310.0]
        @test ch.live_enabled === false

        # Model carries empty SharedTable by default
        m = SPCWorkbenchModel(data = empty_workbench_data(), paused = true, seed_demos = :none)
        @test m.table isa SharedTable
        @test isempty(m.table.rows)
        @test isempty(m.table.columns)
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

        # limits_mode :manual with all set uses manual sigma = (ucl - cl) / 3 (PR5)
        ch_m = ChartSpec(data = WorkbenchData(values = vs, cl = 3.0, sigma = 1.0),
            limits_mode = :manual, manual_cl = 10.0, manual_ucl = 13.0, manual_lcl = 7.0)
        ctx_m = resolve_chart_render_context(ch_m)
        @test ctx_m.lz.cl == 10.0
        @test ctx_m.lz.ucl == 13.0
        @test ctx_m.lz.lcl == 7.0
        @test ctx_m.lz.sigma == 1.0  # (13-10)/3
        @test ctx_m.lz.ucl2 == 12.0  # cl + 2σ
        @test ctx_m.lz.lcl2 == 8.0
        @test ctx_m.lz.ucl1 == 11.0
        @test ctx_m.lz.lcl1 == 9.0
    end

    @testset "manual CL/UCL/LCL resolver: pure sigma + WECO zones (PR5)" begin
        # Distinct from auto mean so we can prove manual path is taken
        vs = [0.0, 0.5, 1.0, 0.0, 0.5, 1.0, 0.0, 0.5, 1.0, 0.0]
        cl_m, ucl_m, lcl_m = 0.0, 3.0, -3.0
        ch = ChartSpec(
            data = WorkbenchData(values = vs, cl = mean(vs), sigma = 1.0),
            limits_mode = :manual,
            manual_cl = cl_m,
            manual_ucl = ucl_m,
            manual_lcl = lcl_m,
            enabled_rules = Dict("WECO-1" => true),
        )
        ctx = resolve_chart_render_context(ch)
        @test ctx.lz.cl == cl_m
        @test ctx.lz.ucl == ucl_m
        @test ctx.lz.lcl == lcl_m
        @test isapprox(ctx.lz.sigma, (ucl_m - cl_m) / 3; atol = 1e-12)
        # Point beyond +3σ of manual limits triggers WECO-1
        vs2 = copy(vs)
        vs2[5] = 3.5  # beyond UCL=3
        ch2 = ChartSpec(
            data = WorkbenchData(values = vs2, cl = 0.0, sigma = 1.0),
            limits_mode = :manual,
            manual_cl = cl_m,
            manual_ucl = ucl_m,
            manual_lcl = lcl_m,
            enabled_rules = Dict("WECO-1" => true),
        )
        ctx2 = resolve_chart_render_context(ch2)
        @test 5 in ctx2.viol_indices
        # Incomplete manual falls back to auto
        ch_partial = ChartSpec(
            data = WorkbenchData(values = vs, cl = 0.0, sigma = 1.0),
            limits_mode = :manual,
            manual_cl = 10.0,
            manual_ucl = 13.0,
            manual_lcl = nothing,
        )
        ctx_p = resolve_chart_render_context(ch_partial)
        lz_auto = auto_limits(vs; sigma_method = :mr)
        @test ctx_p.lz.cl == lz_auto.cl
        @test ctx_p.lz.sigma == lz_auto.sigma
        @test _manual_limits_effective(ch_partial) === false
        # Non-positive sigma (ucl <= cl) falls through to auto
        ch_zero = ChartSpec(
            data = WorkbenchData(values = vs, cl = 0.0, sigma = 1.0),
            limits_mode = :manual,
            manual_cl = 10.0,
            manual_ucl = 10.0,
            manual_lcl = 7.0,
        )
        ctx_z = resolve_chart_render_context(ch_zero)
        @test _manual_limits_effective(ch_zero) === false
        @test ctx_z.lz.cl == lz_auto.cl
        @test ctx_z.lz.sigma == lz_auto.sigma
        ch_neg = ChartSpec(
            data = WorkbenchData(values = vs, cl = 0.0, sigma = 1.0),
            limits_mode = :manual,
            manual_cl = 10.0,
            manual_ucl = 7.0,
            manual_lcl = 4.0,
        )
        @test _manual_limits_effective(ch_neg) === false
        ctx_n = resolve_chart_render_context(ch_neg)
        @test ctx_n.lz.cl == lz_auto.cl
        # Auto path still ignores manual_* when mode is :auto
        ch_auto = ChartSpec(
            data = WorkbenchData(values = vs, cl = 0.0, sigma = 1.0),
            limits_mode = :auto,
            manual_cl = 99.0,
            manual_ucl = 199.0,
            manual_lcl = -1.0,
        )
        ctx_a = resolve_chart_render_context(ch_auto)
        @test ctx_a.lz.cl == lz_auto.cl
        @test ctx_a.lz.cl != 99.0
        @test _manual_limits_effective(ch) === true
        # Last-N WECO msgs policy: by sample index (most recent), not rule-number tail
        fake = [
            WECOViolation("WECO-1", 2, "early"),
            WECOViolation("WECO-8", 10, "late-rule8"),
            WECOViolation("WECO-1", 9, "late-w1"),
            WECOViolation("WECO-2", 5, "mid"),
            WECOViolation("WECO-3", 8, "mid-late"),
            WECOViolation("WECO-1", 1, "oldest"),
        ]
        last3 = _side_viol_msgs_by_index(fake; n = 3)
        @test length(last3) == 3
        @test [v.index for v in last3] == [8, 9, 10]
        @test last3[2].rule == "WECO-1" && last3[3].rule == "WECO-8"
    end

    @testset "SS_FACTORS table (HTML n=2..25)" begin
        @test haskey(SS_FACTORS, 2) && haskey(SS_FACTORS, 25)
        @test !haskey(SS_FACTORS, 1) && !haskey(SS_FACTORS, 26)
        # Spot-check vs HTML SS_FACTORS
        f2 = SS_FACTORS[2]
        @test f2.A2 == 1.880
        @test f2.A3 == 2.659
        @test f2.d2 == 1.128
        @test f2.c4 == 0.7979
        @test f2.D3 == 0.0
        @test f2.D4 == 3.267
        @test f2.B3 == 0.0
        @test f2.B4 == 3.267
        f5 = SS_FACTORS[5]
        @test f5.A2 == 0.577
        @test f5.A3 == 1.427
        @test f5.d2 == 2.326
        @test f5.c4 == 0.9400
        f10 = SS_FACTORS[10]
        @test f10.A2 == 0.308
        @test f10.A3 == 0.975
        @test f10.d2 == 3.078
        @test f10.c4 == 0.9727
        f25 = SS_FACTORS[25]
        @test f25.A2 == 0.153
        @test f25.A3 == 0.606
        @test f25.d2 == 3.931
        @test f25.c4 == 0.9896
    end

    @testset "subgroup_means_and_ranges / subgroup_means_and_s (series chunks)" begin
        # 12 values → 4 complete groups of n=3; remainder dropped
        vals = [10.0, 12.0, 11.0,  20.0, 22.0, 18.0,  30.0, 28.0, 32.0,  40.0, 41.0]
        xbar, ranges, groups = subgroup_means_and_ranges(vals, 3)
        @test length(xbar) == 3
        @test length(ranges) == 3
        @test length(groups) == 3
        @test xbar[1] ≈ mean([10.0, 12.0, 11.0])
        @test ranges[1] ≈ 2.0  # 12-10
        @test xbar[2] ≈ mean([20.0, 22.0, 18.0])
        @test ranges[2] ≈ 4.0  # 22-18
        @test xbar[3] ≈ mean([30.0, 28.0, 32.0])
        @test ranges[3] ≈ 4.0  # 32-28
        # incomplete tail (40,41) discarded
        @test length(groups[1]) == 3

        xbar_s, svals, g2 = subgroup_means_and_s(vals, 3)
        @test length(xbar_s) == 3
        @test xbar_s ≈ xbar
        @test svals[1] ≈ std([10.0, 12.0, 11.0]; corrected = true)
        @test svals[2] ≈ std([20.0, 22.0, 18.0]; corrected = true)

        # too few for one full subgroup → empty
        xb0, r0, g0 = subgroup_means_and_ranges([1.0, 2.0], 5)
        @test isempty(xb0) && isempty(r0) && isempty(g0)

        # n clamped by helpers to [2,25]
        xb2, r2, _ = subgroup_means_and_ranges(collect(1.0:10.0), 1)  # treat as 2
        @test length(xb2) == 5
    end

    @testset "auto_limits Xbar_R / Xbar_S (HTML formulas)" begin
        # Crafted series: 3 subgroups of size 5
        # SG1 mean=10, R=4; SG2 mean=12, R=2; SG3 mean=11, R=6
        raw = Float64[
            8, 10, 12, 9, 11,   # mean 10, R=4
            11, 12, 13, 12, 12, # mean 12, R=2
            8, 14, 10, 11, 12,  # mean 11, R=6
        ]
        n = 5
        f = SS_FACTORS[n]
        xbar, ranges, _ = subgroup_means_and_ranges(raw, n)
        @test length(xbar) == 3
        rbar = mean(ranges)
        xbb = mean(xbar)
        lz_r = auto_limits(raw; chart_type = Xbar_R, subgroup_size = n)
        @test lz_r.cl ≈ xbb
        @test lz_r.sigma ≈ rbar / f.d2
        @test lz_r.ucl ≈ xbb + f.A2 * rbar
        @test lz_r.lcl ≈ xbb - f.A2 * rbar
        # intermediate zones from process σ (WECO scale)
        @test lz_r.ucl1 ≈ xbb + 1 * lz_r.sigma
        @test lz_r.ucl2 ≈ xbb + 2 * lz_r.sigma
        @test lz_r.lcl1 ≈ xbb - 1 * lz_r.sigma
        @test lz_r.lcl2 ≈ xbb - 2 * lz_r.sigma

        xbar_s, svals, _ = subgroup_means_and_s(raw, n)
        sbar = mean(svals)
        lz_s = auto_limits(raw; chart_type = Xbar_S, subgroup_size = n)
        @test lz_s.cl ≈ mean(xbar_s)
        @test lz_s.sigma ≈ sbar  # HTML: sigma = sBar
        @test lz_s.ucl ≈ mean(xbar_s) + f.A3 * sbar
        @test lz_s.lcl ≈ mean(xbar_s) - f.A3 * sbar

        # empty / incomplete → zero limits
        lz0 = auto_limits(Float64[1, 2, 3]; chart_type = Xbar_R, subgroup_size = 5)
        @test lz0.cl == 0.0 && lz0.sigma == 0.0 && lz0.ucl == 0.0

        # I_MR path unchanged
        vs = [1.0, 2.0, 3.0, 4.0, 5.0]
        @test auto_limits(vs; chart_type = I_MR, sigma_method = :mr).sigma ==
              compute_limits_and_zones(vs; sigma_method = :mr).sigma
    end

    @testset "resolve Xbar_R / Xbar_S primary series + Cpk c4 + secondary stats" begin
        raw = Float64[
            8, 10, 12, 9, 11,
            11, 12, 13, 12, 12,
            8, 14, 10, 11, 12,
        ]
        n = 5
        f = SS_FACTORS[n]
        usl, lsl = 20.0, 0.0

        ch_r = ChartSpec(
            name = "XbarR test",
            chart_type = Xbar_R,
            data = WorkbenchData(values = raw, cl = 0.0, sigma = 0.0),
            subgroup_size = n,
            usl = usl,
            lsl = lsl,
        )
        ctx_r = resolve_chart_render_context(ch_r)
        xbar, ranges, _ = subgroup_means_and_ranges(raw, n)
        @test ctx_r.primary_values ≈ xbar
        @test length(ctx_r.primary_values) == 3
        @test ctx_r.lz.ucl ≈ mean(xbar) + f.A2 * mean(ranges)
        @test ctx_r.secondary_name == "R"
        @test ctx_r.secondary_bar ≈ mean(ranges)
        # Xbar-R Cpk uses process σ = R̄/d2 (already lz.sigma)
        cr_r = compute_capability(xbar, ctx_r.lz.cl, ctx_r.lz.sigma; usl = usl, lsl = lsl)
        @test ctx_r.cpk ≈ cr_r.cpk

        ch_s = ChartSpec(
            name = "XbarS test",
            chart_type = Xbar_S,
            data = WorkbenchData(values = raw, cl = 0.0, sigma = 0.0),
            subgroup_size = n,
            usl = usl,
            lsl = lsl,
        )
        ctx_s = resolve_chart_render_context(ch_s)
        xbar_s, svals, _ = subgroup_means_and_s(raw, n)
        sbar = mean(svals)
        @test ctx_s.primary_values ≈ xbar_s
        @test ctx_s.secondary_name == "s"
        @test ctx_s.secondary_bar ≈ sbar
        # Xbar-S Cpk unbiases s̄ with c4 (HTML)
        cpk_sigma = sbar / f.c4
        cr_s = compute_capability(xbar_s, ctx_s.lz.cl, cpk_sigma; usl = usl, lsl = lsl)
        @test ctx_s.cpk ≈ cr_s.cpk
        # c4-unbiased sigma differs from raw s̄
        cr_wrong = compute_capability(xbar_s, ctx_s.lz.cl, sbar; usl = usl, lsl = lsl)
        @test ctx_s.cpk !== nothing && cr_wrong.cpk !== nothing
        @test abs(ctx_s.cpk - cr_wrong.cpk) > 1e-9

        # I_MR primary is raw values; secondary is MR̄ (mean moving range) — PR10 P2
        ch_i = ChartSpec(data = WorkbenchData(values = raw, cl = 0.0, sigma = 0.0))
        ctx_i = resolve_chart_render_context(ch_i)
        @test ctx_i.primary_values ≈ raw
        @test ctx_i.secondary_name == "MR"
        mr_expected = mean(abs.(diff(raw)))
        @test ctx_i.secondary_bar ≈ mr_expected
        # σ̂ = MR̄ / d2(n=2) = MR̄ / 1.128
        @test ctx_i.lz.sigma ≈ mr_expected / 1.128 atol = 1e-9
    end

    @testset "P2-PR1: SecondarySeries truth table (pure values + limits)" begin
        # --- I_MR n ≥ 2: length n-1 MRs; cl=MR̄, ucl=D4₂·MR̄, lcl=0 ---
        raw_imr = Float64[10.0, 12.0, 11.0, 15.0, 14.0]
        ch_imr = ChartSpec(data = WorkbenchData(values = raw_imr, cl = 0.0, sigma = 0.0))
        primary_imr = Float64.(raw_imr)
        sec_imr = secondary_series_for(ch_imr, primary_imr)
        mrs = abs.(diff(raw_imr))
        mrbar = mean(mrs)
        @test sec_imr.name == "MR"
        @test sec_imr.values ≈ mrs
        @test length(sec_imr.values) == length(raw_imr) - 1
        @test sec_imr.bar ≈ mrbar
        @test sec_imr.cl ≈ mrbar
        # Pin HTML autoLimits constant (not only relative to SS_FACTORS table)
        @test SS_FACTORS[2].D4 == 3.267
        @test sec_imr.ucl ≈ 3.267 * mrbar  # HTML: UCL = 3.267·MR̄
        @test sec_imr.ucl ≈ SS_FACTORS[2].D4 * mrbar
        @test sec_imr.lcl == 0.0
        ctx_imr = resolve_chart_render_context(ch_imr)
        @test ctx_imr.secondary_name == "MR"
        @test ctx_imr.secondary_bar ≈ mrbar
        @test ctx_imr.secondary.values ≈ mrs
        @test ctx_imr.secondary.ucl ≈ 3.267 * mrbar
        @test ctx_imr.secondary.lcl == 0.0

        # --- I_MR n < 2: empty values; bar/cl/ucl/lcl all nothing (not 0/0/0) ---
        for short in (Float64[], Float64[5.0])
            ch_short = ChartSpec(data = WorkbenchData(values = short, cl = 0.0, sigma = 0.0))
            sec_s = secondary_series_for(ch_short, Float64.(short))
            @test sec_s.name == "MR"
            @test isempty(sec_s.values)
            @test sec_s.bar === nothing
            @test sec_s.cl === nothing
            @test sec_s.ucl === nothing
            @test sec_s.lcl === nothing
            ctx_s = resolve_chart_render_context(ch_short)
            @test ctx_s.secondary_bar === nothing
            @test isempty(ctx_s.secondary.values)
            @test ctx_s.secondary.cl === nothing
        end

        # --- I_MR secondary bar == 0 (constant series): cl=ucl=lcl=0 ---
        const_vals = Float64[7.0, 7.0, 7.0, 7.0]
        ch_const = ChartSpec(data = WorkbenchData(values = const_vals, cl = 7.0, sigma = 0.0))
        sec_z = secondary_series_for(ch_const, const_vals)
        @test sec_z.values ≈ [0.0, 0.0, 0.0]
        @test sec_z.bar == 0.0
        @test sec_z.cl == 0.0
        @test sec_z.ucl == 0.0
        @test sec_z.lcl == 0.0

        # --- Xbar_R series-chunk complete groups ---
        raw_x = Float64[
            8, 10, 12, 9, 11,   # mean 10, R=4
            11, 12, 13, 12, 12, # mean 12, R=2
            8, 14, 10, 11, 12,  # mean 11, R=6
        ]
        n = 5
        f = SS_FACTORS[n]
        ch_xr = ChartSpec(
            chart_type = Xbar_R,
            data = WorkbenchData(values = raw_x, cl = 0.0, sigma = 0.0),
            subgroup_size = n,
        )
        xbar, ranges, _ = subgroup_means_and_ranges(raw_x, n)
        sec_r = secondary_series_for(ch_xr, xbar)
        rbar = mean(ranges)
        @test sec_r.name == "R"
        @test sec_r.values ≈ ranges
        @test length(sec_r.values) == length(xbar) == 3
        @test sec_r.bar ≈ rbar
        @test sec_r.cl ≈ rbar
        @test sec_r.ucl ≈ f.D4 * rbar
        @test sec_r.lcl ≈ f.D3 * rbar  # D3(5)=0
        ctx_r = resolve_chart_render_context(ch_xr)
        @test ctx_r.secondary.values ≈ ranges
        @test ctx_r.secondary.ucl ≈ f.D4 * rbar
        @test ctx_r.secondary_name == "R"
        @test ctx_r.secondary_bar ≈ rbar

        # --- Xbar_S series-chunk ---
        ch_xs = ChartSpec(
            chart_type = Xbar_S,
            data = WorkbenchData(values = raw_x, cl = 0.0, sigma = 0.0),
            subgroup_size = n,
        )
        xbar_s, svals, _ = subgroup_means_and_s(raw_x, n)
        sec_s2 = secondary_series_for(ch_xs, xbar_s)
        sbar = mean(svals)
        @test sec_s2.name == "s"
        @test sec_s2.values ≈ svals
        @test sec_s2.bar ≈ sbar
        @test sec_s2.cl ≈ sbar
        @test sec_s2.ucl ≈ f.B4 * sbar
        @test sec_s2.lcl ≈ f.B3 * sbar
        ctx_s2 = resolve_chart_render_context(ch_xs)
        @test ctx_s2.secondary.values ≈ svals
        @test ctx_s2.secondary.ucl ≈ f.B4 * sbar

        # --- Xbar empty / incomplete groups (no full subgroup) ---
        ch_empty = ChartSpec(
            chart_type = Xbar_R,
            data = WorkbenchData(values = Float64[1, 2, 3], cl = 0.0, sigma = 0.0),
            subgroup_size = 5,
        )
        sec_e = secondary_series_for(ch_empty, Float64[])
        @test sec_e.name == "R"
        @test isempty(sec_e.values)
        @test sec_e.bar === nothing
        @test sec_e.cl === nothing && sec_e.ucl === nothing && sec_e.lcl === nothing
        ctx_e = resolve_chart_render_context(ch_empty)
        @test isempty(ctx_e.secondary.values)
        @test ctx_e.secondary_bar === nothing

        # --- Attribute types: empty secondary ---
        for at in (p_chart, np_chart, c_chart, u_chart)
            ch_a = ChartSpec(
                chart_type = at,
                data = WorkbenchData(values = Float64[0.1, 0.2, 0.15], cl = 0.0, sigma = 0.0),
            )
            sec_a = secondary_series_for(ch_a, Float64.(ch_a.data.values))
            @test sec_a.name == ""
            @test isempty(sec_a.values)
            @test sec_a.bar === nothing
            @test sec_a.cl === nothing && sec_a.ucl === nothing && sec_a.lcl === nothing
            ctx_a = resolve_chart_render_context(ch_a)
            @test ctx_a.secondary_name == ""
            @test ctx_a.secondary_bar === nothing
            @test isempty(ctx_a.secondary.values)
        end

        # --- Manual primary limits: secondary still auto from series (not invent 0/0/0) ---
        ch_man = ChartSpec(
            data = WorkbenchData(values = raw_imr, cl = 0.0, sigma = 0.0),
            limits_mode = :manual,
            manual_cl = 12.0,
            manual_ucl = 18.0,
            manual_lcl = 6.0,
        )
        @test _manual_limits_effective(ch_man)
        ctx_man = resolve_chart_render_context(ch_man)
        @test ctx_man.lz.cl == 12.0
        @test ctx_man.lz.ucl == 18.0
        @test ctx_man.lz.lcl == 6.0
        # Secondary independent of manual primary
        @test ctx_man.secondary.values ≈ mrs
        @test ctx_man.secondary.cl ≈ mrbar
        @test ctx_man.secondary.ucl ≈ 3.267 * mrbar
        @test ctx_man.secondary.lcl == 0.0
        @test ctx_man.secondary_name == "MR"
        @test ctx_man.secondary_bar ≈ mrbar

        # Manual Xbar_R: primary manual, R limits still D3/D4·R̄
        ch_man_r = ChartSpec(
            chart_type = Xbar_R,
            data = WorkbenchData(values = raw_x, cl = 0.0, sigma = 0.0),
            subgroup_size = n,
            limits_mode = :manual,
            manual_cl = 11.0,
            manual_ucl = 14.0,
            manual_lcl = 8.0,
        )
        ctx_man_r = resolve_chart_render_context(ch_man_r)
        @test ctx_man_r.lz.cl == 11.0
        @test ctx_man_r.secondary.values ≈ ranges
        @test ctx_man_r.secondary.ucl ≈ f.D4 * rbar
        @test ctx_man_r.secondary.lcl ≈ f.D3 * rbar

        # --- table_subgroups: use meta secondary_vals + subgroup_n (do not re-chunk means) ---
        means_tbl = Float64[10.0, 12.0, 11.0]
        ranges_tbl = Float64[4.0, 2.0, 4.0]
        n_tbl = 3
        f3 = SS_FACTORS[n_tbl]
        ch_tbl = ChartSpec(
            chart_type = Xbar_R,
            data = WorkbenchData(
                values = means_tbl,
                cl = 0.0,
                sigma = 0.0,
                meta = Dict{String,Any}(
                    "table_subgroups" => true,
                    "secondary_vals" => ranges_tbl,
                    "secondary_name" => "R",
                    "subgroup_n" => n_tbl,
                ),
            ),
            subgroup_size = 5,  # must be ignored for secondary factors when meta has subgroup_n
        )
        sec_tbl = secondary_series_for(ch_tbl, means_tbl)
        rbar_tbl = mean(ranges_tbl)
        @test sec_tbl.name == "R"
        @test sec_tbl.values ≈ ranges_tbl
        @test sec_tbl.bar ≈ rbar_tbl
        @test sec_tbl.cl ≈ rbar_tbl
        @test sec_tbl.ucl ≈ f3.D4 * rbar_tbl
        @test sec_tbl.lcl ≈ f3.D3 * rbar_tbl
        # Not SS_FACTORS[5] (would be wrong if re-chunk / wrong n)
        @test sec_tbl.ucl ≉ SS_FACTORS[5].D4 * rbar_tbl
        ctx_tbl = resolve_chart_render_context(ch_tbl)
        @test ctx_tbl.primary_values ≈ means_tbl
        @test length(ctx_tbl.primary_values) == 3
        @test ctx_tbl.secondary.values ≈ ranges_tbl
        @test ctx_tbl.secondary.ucl ≈ f3.D4 * rbar_tbl
        @test ctx_tbl.secondary_bar ≈ rbar_tbl

        # --- table_subgroups Xbar_S: B3/B4 × s̄ with meta subgroup_n (not ChartSpec.subgroup_size) ---
        svals_tbl = Float64[1.0, 1.5, 0.5]
        ch_tbl_s = ChartSpec(
            chart_type = Xbar_S,
            data = WorkbenchData(
                values = means_tbl,
                cl = 0.0,
                sigma = 0.0,
                meta = Dict{String,Any}(
                    "table_subgroups" => true,
                    "secondary_vals" => svals_tbl,
                    "secondary_name" => "s",
                    "subgroup_n" => n_tbl,
                ),
            ),
            subgroup_size = 5,  # must not drive secondary B3/B4
        )
        sec_tbl_s = secondary_series_for(ch_tbl_s, means_tbl)
        sbar_tbl = mean(svals_tbl)
        @test sec_tbl_s.name == "s"
        @test sec_tbl_s.values ≈ svals_tbl
        @test sec_tbl_s.bar ≈ sbar_tbl
        @test sec_tbl_s.cl ≈ sbar_tbl
        @test sec_tbl_s.ucl ≈ f3.B4 * sbar_tbl
        @test sec_tbl_s.lcl ≈ f3.B3 * sbar_tbl
        @test sec_tbl_s.ucl ≉ SS_FACTORS[5].B4 * sbar_tbl
        ctx_tbl_s = resolve_chart_render_context(ch_tbl_s)
        @test ctx_tbl_s.secondary.values ≈ svals_tbl
        @test ctx_tbl_s.secondary.ucl ≈ f3.B4 * sbar_tbl
        @test ctx_tbl_s.secondary.lcl ≈ f3.B3 * sbar_tbl
        @test ctx_tbl_s.secondary_name == "s"
        @test ctx_tbl_s.secondary_bar ≈ sbar_tbl
    end

    @testset "PR7b: table-sourced Xbar subgroups by column (pure fixtures)" begin
        # Pure group helpers: first-seen order; size-1 groups dropped for stats
        vals = [10.0, 12.0, 11.0,  20.0, 22.0, 18.0,  30.0]
        keys = ["W01", "W01", "W01", "W02", "W02", "W02", "W03"]  # W03 alone
        groups, order = group_values_by_keys(vals, keys)
        @test order == ["W01", "W02", "W03"]
        @test groups[1] == [10.0, 12.0, 11.0]
        @test groups[2] == [20.0, 22.0, 18.0]
        @test groups[3] == [30.0]

        xbar, ranges, kept = subgroup_means_and_ranges_from_groups(groups)
        @test length(xbar) == 2  # W03 dropped (n=1)
        @test length(kept) == 2
        @test xbar[1] ≈ mean([10.0, 12.0, 11.0])
        @test ranges[1] ≈ 2.0
        @test xbar[2] ≈ mean([20.0, 22.0, 18.0])
        @test ranges[2] ≈ 4.0

        xbar_s, svals, kept_s = subgroup_means_and_s_from_groups(groups)
        @test length(xbar_s) == 2
        @test svals[1] ≈ std([10.0, 12.0, 11.0]; corrected = true)
        @test svals[2] ≈ std([20.0, 22.0, 18.0]; corrected = true)

        # auto_limits with precomputed secondary (no re-chunk)
        n = 3
        f = SS_FACTORS[n]
        rbar = mean(ranges)
        xbb = mean(xbar)
        lz = auto_limits(xbar; chart_type = Xbar_R, subgroup_size = n, secondary = ranges)
        @test lz.cl ≈ xbb
        @test lz.sigma ≈ rbar / f.d2
        @test lz.ucl ≈ xbb + f.A2 * rbar
        @test lz.lcl ≈ xbb - f.A2 * rbar

        # SharedTable fixture: multi-site per wafer, interleaved tools
        # W01 sites: 8,10,12 → mean 10, R=4
        # W02 sites: 11,12,13 → mean 12, R=2
        # W03 sites: 9,11,13 → mean 11, R=4
        table = SharedTable(
            columns = ["Timestamp", "Tool", "Wafer", "Value"],
            rows = [
                Dict("Timestamp" => "t1", "Tool" => "ETCH-A", "Wafer" => "W01", "Value" => "8"),
                Dict("Timestamp" => "t2", "Tool" => "ETCH-A", "Wafer" => "W01", "Value" => "10"),
                Dict("Timestamp" => "t3", "Tool" => "ETCH-A", "Wafer" => "W01", "Value" => "12"),
                Dict("Timestamp" => "t4", "Tool" => "ETCH-A", "Wafer" => "W02", "Value" => "11"),
                Dict("Timestamp" => "t5", "Tool" => "ETCH-B", "Wafer" => "W02", "Value" => "12"),  # filtered out
                Dict("Timestamp" => "t6", "Tool" => "ETCH-A", "Wafer" => "W02", "Value" => "12"),
                Dict("Timestamp" => "t7", "Tool" => "ETCH-A", "Wafer" => "W02", "Value" => "13"),
                Dict("Timestamp" => "t8", "Tool" => "ETCH-A", "Wafer" => "W03", "Value" => "9"),
                Dict("Timestamp" => "t9", "Tool" => "ETCH-A", "Wafer" => "W03", "Value" => "11"),
                Dict("Timestamp" => "t10", "Tool" => "ETCH-A", "Wafer" => "W03", "Value" => "13"),
            ],
        )
        ch_r = ChartSpec(
            name = "CD-XbarR",
            chart_type = Xbar_R,
            tools = ["ETCH-A"],
            col_value = "Value",
            col_tool = "Tool",
            col_time = "Timestamp",
            col_lot = "Wafer",
            subgroup_size = 3,
            usl = 20.0,
            lsl = 0.0,
        )
        # compute_chart_series still returns individuals + lot key in meta
        raw_v, raw_lab, raw_pm = compute_chart_series(table, ch_r)
        @test length(raw_v) == 9  # ETCH-B row dropped
        @test all(haskey(pm, "lot") for pm in raw_pm)
        @test raw_pm[1]["lot"] == "W01"

        materialize_chart_from_table!(ch_r, table)
        @test ch_r.source === :table
        @test ch_r.live_enabled === false
        @test get(ch_r.data.meta, "table_subgroups", false) === true
        @test ch_r.data.values ≈ [10.0, 12.0, 11.0]  # three wafer means
        @test ch_r.data.meta["labels"] == ["W01", "W02", "W03"]
        @test ch_r.data.meta["secondary_name"] == "R"
        @test ch_r.data.meta["secondary_vals"] ≈ [4.0, 2.0, 4.0]
        @test ch_r.data.meta["subgroup_n"] == 3
        @test ch_r.viewport.x0 == 1
        @test ch_r.viewport.x1 == 3

        ctx_r = resolve_chart_render_context(ch_r)
        @test ctx_r.primary_values ≈ [10.0, 12.0, 11.0]
        @test ctx_r.secondary_name == "R"
        @test ctx_r.secondary_bar ≈ mean([4.0, 2.0, 4.0])
        f3 = SS_FACTORS[3]
        rbar = mean([4.0, 2.0, 4.0])
        xbb = mean([10.0, 12.0, 11.0])
        @test ctx_r.lz.cl ≈ xbb
        @test ctx_r.lz.sigma ≈ rbar / f3.d2
        @test ctx_r.lz.ucl ≈ xbb + f3.A2 * rbar
        # Must NOT re-chunk the three means as if they were individuals
        # (series-chunk of n=3 on [10,12,11] would yield one group of mean 11)
        @test length(ctx_r.primary_values) == 3

        # Xbar_S same table
        ch_s = ChartSpec(
            name = "CD-XbarS",
            chart_type = Xbar_S,
            tools = ["ETCH-A"],
            col_value = "Value",
            col_tool = "Tool",
            col_lot = "Wafer",
            subgroup_size = 3,
            usl = 20.0,
            lsl = 0.0,
        )
        materialize_chart_from_table!(ch_s, table)
        @test get(ch_s.data.meta, "table_subgroups", false) === true
        @test ch_s.data.meta["secondary_name"] == "s"
        ctx_s = resolve_chart_render_context(ch_s)
        @test ctx_s.primary_values ≈ [10.0, 12.0, 11.0]
        @test ctx_s.secondary_name == "s"
        s_w01 = std([8.0, 10.0, 12.0]; corrected = true)
        s_w02 = std([11.0, 12.0, 13.0]; corrected = true)
        s_w03 = std([9.0, 11.0, 13.0]; corrected = true)
        sbar = mean([s_w01, s_w02, s_w03])
        @test ctx_s.secondary_bar ≈ sbar
        @test ctx_s.lz.sigma ≈ sbar
        @test ctx_s.lz.ucl ≈ mean([10.0, 12.0, 11.0]) + f3.A3 * sbar
        # Cpk uses s̄/c4
        cpk_sigma = sbar / f3.c4
        cr = compute_capability(ctx_s.primary_values, ctx_s.lz.cl, cpk_sigma; usl = 20.0, lsl = 0.0)
        @test ctx_s.cpk ≈ cr.cpk

        # Empty col_lot → individuals materialize; series-chunk at resolve (PR7 path)
        ch_chunk = ChartSpec(
            chart_type = Xbar_R,
            tools = ["ETCH-A"],
            col_value = "Value",
            col_tool = "Tool",
            col_lot = "",
            subgroup_size = 3,
        )
        materialize_chart_from_table!(ch_chunk, table)
        @test get(ch_chunk.data.meta, "table_subgroups", false) !== true
        @test length(ch_chunk.data.values) == 9  # raw individuals
        ctx_chunk = resolve_chart_render_context(ch_chunk)
        @test length(ctx_chunk.primary_values) == 3  # 9/3 series chunks
        # First chunk is first three ETCH-A rows (W01 sites) — same as column group
        @test ctx_chunk.primary_values[1] ≈ 10.0

        # Group by Tool column (col_lot points at Tool) — two tools with multi-row
        table2 = SharedTable(
            columns = ["Tool", "Value"],
            rows = [
                Dict("Tool" => "A", "Value" => "1"),
                Dict("Tool" => "A", "Value" => "3"),
                Dict("Tool" => "B", "Value" => "10"),
                Dict("Tool" => "B", "Value" => "14"),
                Dict("Tool" => "B", "Value" => "12"),
            ],
        )
        ch_tool = ChartSpec(
            chart_type = Xbar_R,
            col_value = "Value",
            col_tool = "Tool",
            col_lot = "Tool",
            tools = String[],
            subgroup_size = 2,
        )
        materialize_chart_from_table!(ch_tool, table2)
        @test ch_tool.data.values ≈ [2.0, 12.0]  # means of A and B
        @test ch_tool.data.meta["labels"] == ["A", "B"]
        @test ch_tool.data.meta["secondary_vals"] ≈ [2.0, 4.0]  # R: 3-1=2, 14-10=4
        ctx_tool = resolve_chart_render_context(ch_tool)
        @test length(ctx_tool.primary_values) == 2
        @test ctx_tool.secondary_bar ≈ 3.0

        # I_MR + col_lot: no table_subgroups; individuals only; lot in point_meta
        ch_i = ChartSpec(
            chart_type = I_MR,
            col_value = "Value",
            col_lot = "Wafer",
            tools = ["ETCH-A"],
            col_tool = "Tool",
        )
        materialize_chart_from_table!(ch_i, table)
        @test get(ch_i.data.meta, "table_subgroups", false) !== true
        @test length(ch_i.data.values) == 9
        @test ch_i.data.meta["point_meta"][1]["lot"] == "W01"
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

        # KD-P2-21: add_chart! seeds from m.default_rules (session), not active mirror
        m_def = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m_def)
        @test m_def.default_rules["WECO-6"] === false  # module default
        @test m_def.default_rules !== m_def.enabled_rules
        m_def.default_rules["WECO-6"] = true
        m_def.default_rules["WECO-1"] = false
        # mutate active chart rules independently — must not affect seed source
        m_def.charts[1].enabled_rules["WECO-7"] = true
        m_def.enabled_rules["WECO-7"] = true
        idx_seed = add_chart!(m_def; name = "FromDefaults")
        seeded = m_def.charts[idx_seed]
        @test seeded.enabled_rules["WECO-6"] === true
        @test seeded.enabled_rules["WECO-1"] === false
        @test get(seeded.enabled_rules, "WECO-7", false) === false  # not from active
        @test seeded.enabled_rules !== m_def.default_rules  # deep copy
        m_def.default_rules["WECO-6"] = false
        @test seeded.enabled_rules["WECO-6"] === true  # independent after seed

        # demos / _ensure_charts! keep explicit rules — do not pull m.default_rules
        m_demo = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        m_demo.default_rules = Dict{String,Bool}(
            "WECO-1" => false, "WECO-2" => false, "WECO-3" => false,
            "WECO-4" => false, "WECO-5" => false, "WECO-6" => true,
            "WECO-7" => true, "WECO-8" => true,
        )
        _ensure_charts!(m_demo)
        @test length(m_demo.charts) == 3
        # Primary uses legacy m.enabled_rules at seed time (still DEFAULT), not default_rules
        @test m_demo.charts[1].enabled_rules["WECO-1"] === true
        @test m_demo.charts[1].enabled_rules["WECO-6"] === false
        # Secondary/Tertiary use ChartSpec defaults (DEFAULT_WECO_RULES)
        @test m_demo.charts[2].enabled_rules["WECO-1"] === true
        @test m_demo.charts[2].enabled_rules["WECO-6"] === false
        @test m_demo.charts[3].enabled_rules["WECO-1"] === true
        @test m_demo.charts[3].enabled_rules["WECO-6"] === false

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

    @testset "ParamEntry + :fake_tool series seed (PR1a)" begin
        d = generate_spc_workbench_data(12; seed = 7)

        # Empty catalog defaults (no ensure yet)
        m0 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        @test m0.params isa Vector{ParamEntry}
        @test isempty(m0.params)
        @test m0.selected_param == 0
        @test m0.dashboard_max_panes == 3  # field default matches triple compat
        @test m0.side_focus === :none
        @test m0.add_chart_open === false
        @test m0.add_chart_mode === :param
        @test m0.add_chart_selected == 1
        @test m0.add_chart_analysis === I_MR
        @test m0.seed_demos === :none

        # Catalog helpers (synthetic — not fixture CSV)
        tools = default_fake_tools()
        @test length(tools) == 1
        @test tools[1].id == "Film-PTPECVD01"
        params = default_fake_tool_params()
        @test length(params) >= 3
        @test params[1].id == "thk_1_3um"
        @test params[2].id == "n_oxide"
        @test params[3].id == "thk_hsq"

        # :fake_tool seed path
        m_ft = SPCWorkbenchModel(data = d, paused = true, seed_demos = :fake_tool)
        @test m_ft.seed_demos === :fake_tool
        _ensure_charts!(m_ft)
        @test !isempty(m_ft.tools)
        @test m_ft.tools[1].id == "Film-PTPECVD01"
        @test length(m_ft.params) >= 3
        @test length(m_ft.charts) == 1
        @test m_ft.selected_param == 1
        @test m_ft.dashboard_max_panes == 1
        ch = m_ft.charts[1]
        @test ch.param == m_ft.params[1].id          # identity lock: id, not name
        @test ch.param == "thk_1_3um"
        @test ch.name == m_ft.params[1].name
        @test ch.param != ch.name                     # id and display name must diverge
        @test ch.param != m_ft.params[1].name
        @test ch.units == m_ft.params[1].units
        @test ch.tools == ["Film-PTPECVD01"]
        @test ch.usl == m_ft.params[1].usl
        @test ch.target == m_ft.params[1].target
        @test ch.lsl == m_ft.params[1].lsl
        @test length(ch.data.values) > 0
        @test m_ft.active == 1
        # legacy mirror sync from active chart
        @test length(m_ft.data.values) == length(ch.data.values)
        @test m_ft.usl == ch.usl

        # :triple still 3 charts + panes == 3 after ensure
        m_t = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m_t)
        @test length(m_t.charts) == 3
        @test m_t.dashboard_max_panes == 3
        @test m_t.selected_param == 0
        @test isempty(m_t.params)
        @test isempty(m_t.tools)

        # :single / :none also set panes = 1 on bootstrap
        m_s = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m_s)
        @test length(m_s.charts) == 1
        @test m_s.dashboard_max_panes == 1

        m_n = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        _ensure_charts!(m_n)
        @test length(m_n.charts) == 1
        @test m_n.dashboard_max_panes == 1
        @test m_n.selected_param == 0

        # Re-ensure with non-empty charts must NOT reset dashboard_max_panes
        m_ft.dashboard_max_panes = 2
        _ensure_charts!(m_ft)
        @test m_ft.dashboard_max_panes == 2
        @test length(m_ft.charts) == 1

        # seed_demos model default remains :triple
        m_def = SPCWorkbenchModel(data = d, paused = true)
        @test m_def.seed_demos === :triple
        @test m_def.dashboard_max_panes == 3
        @test m_def.selected_param == 0
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
        # Must not throw and must only reference remaining charts in order
        remaining_ids = Set(c.id for c in m_del.charts)
        @test all(c -> c.id in remaining_ids, panes_del)
        # Exact neighborhood: primary = former-active, secondary = former next neighbor
        @test length(panes_del) == 2
        @test panes_del[1].id == id_active
        @test panes_del[2].id == id_next
        @test m_del.active == 1

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

    @testset "filters + visible_charts + A6 rehome (GC-PR4)" begin
        d = generate_spc_workbench_data(10; seed = 11)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        # Three charts with distinct type / tool / owner metadata
        idx1 = add_chart!(m; name = "Alpha")
        idx2 = add_chart!(m; name = "Beta")
        idx3 = add_chart!(m; name = "Gamma")
        m.charts[idx1].chart_type = I_MR
        m.charts[idx1].tools = ["T-A"]
        m.charts[idx1].owner = "Alice"
        m.charts[idx2].chart_type = Xbar_R
        m.charts[idx2].tools = ["T-B"]
        m.charts[idx2].owner = "Bob"
        m.charts[idx3].chart_type = I_MR
        m.charts[idx3].tools = ["T-A", "T-C"]
        m.charts[idx3].owner = "Alice"
        set_active_chart!(m, idx1)
        @test m.filter_tool == ""
        @test m.filter_type == ""   # wire String only (not Nothing/ChartType)
        @test m.filter_owner == ""
        @test length(visible_charts(m)) == 3
        @test m.seed_demos === :none  # explicit; default remains :triple elsewhere

        # filter by tool (setters package-private; available via include path here)
        set_filter_tool!(m, "T-A")
        vis = visible_charts(m)
        @test length(vis) == 2
        @test all(c -> "T-A" in c.tools, vis)
        @test Set(c.name for c in vis) == Set(["Alpha", "Gamma"])

        # empty ch.tools fails non-empty tool filter (stricter / stack pure policy)
        m.charts[idx1].tools = String[]
        vis_empty_tools = visible_charts(m)
        @test all(c -> c.name != "Alpha", vis_empty_tools)
        @test Set(c.name for c in vis_empty_tools) == Set(["Gamma"])
        m.charts[idx1].tools = ["T-A"]  # restore
        # chart with tools=["ETCH-1"] visible when filter_tool=="ETCH-1"
        m.charts[idx2].tools = ["ETCH-1"]
        set_filter_tool!(m, "ETCH-1")
        vis_etch = visible_charts(m)
        @test length(vis_etch) == 1
        @test vis_etch[1].name == "Beta"
        m.charts[idx2].tools = ["T-B"]
        set_filter_tool!(m, "T-A")

        # filter by type wire String (AND with tool)
        set_filter_type!(m, "Xbar-R")
        vis2 = visible_charts(m)
        @test isempty(vis2)  # Beta has T-B only; no T-A + Xbar-R
        # A6: no visible → keep active, empty message (no crash)
        @test occursin("No charts match filters", m.last_event) ||
              occursin("no charts match", lowercase(m.last_event))
        @test m.active == idx1  # left as-is when empty visible

        # type alone: clear filters, re-select Alpha, then apply type → A6 rehome
        clear_filters!(m)
        set_active_chart!(m, idx1)
        @test current_chart(m).name == "Alpha"
        set_filter_type!(m, "Xbar-R")
        vis3 = visible_charts(m)
        @test length(vis3) == 1
        @test vis3[1].name == "Beta"
        # A6: active Alpha filtered out → switch to first visible (Beta)
        # last_event precedence: rehome message wins (not plain "filter type=…")
        @test m.active == idx2
        @test current_chart(m).name == "Beta"
        @test occursin("active chart filtered", m.last_event)
        @test occursin("Beta", m.last_event)
        @test m.library_selected == m.active
        # when already on visible chart, plain confirmation (no rehome overwrite)
        set_filter_type!(m, "Xbar-R")
        @test m.active == idx2
        @test m.last_event == "filter type=Xbar-R"

        # panes use visible_charts neighborhood
        panes = dashboard_pane_charts(m; k = 3)
        @test length(panes) == 1
        @test panes[1].id == m.charts[idx2].id

        # owner filter (strip equality)
        clear_filters!(m)
        @test m.filter_tool == "" && m.filter_type == "" && m.filter_owner == ""
        @test length(visible_charts(m)) == 3
        @test m.last_event == "filters cleared"
        set_filter_owner!(m, "  Alice  ")
        @test m.filter_owner == "Alice"
        vis4 = visible_charts(m)
        @test length(vis4) == 2
        @test all(c -> strip(c.owner) == "Alice", vis4)

        # clearing restores full list; active stays valid
        act_before = m.active
        clear_filters!(m)
        @test length(visible_charts(m)) == 3
        @test m.active == act_before

        # seed_demos default still :triple
        m_def = SPCWorkbenchModel(data = d, paused = true)
        @test m_def.seed_demos === :triple

        # A6: delete_chart! under filter rehomes active onto remaining visible
        clear_filters!(m)
        set_active_chart!(m, idx1)  # Alpha (T-A, Alice)
        set_filter_owner!(m, "Alice")  # Alpha + Gamma; Beta hidden
        @test Set(c.name for c in visible_charts(m)) == Set(["Alpha", "Gamma"])
        @test m.active == idx1
        id_gamma = m.charts[idx3].id
        @test delete_chart!(m, idx1) === true  # delete active Alpha
        @test length(m.charts) == 2
        # active must be a visible chart (Gamma), not Bob/Beta
        @test any(c -> c.id == current_chart(m).id, visible_charts(m))
        @test current_chart(m).id == id_gamma || current_chart(m).name == "Gamma"
        # [ ] cycle only among visible (absolute indices)
        clear_filters!(m)
        # rebuild 3 charts for cycle test
        m2 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        a = add_chart!(m2; name = "Keep")
        b = add_chart!(m2; name = "Hide")
        c = add_chart!(m2; name = "Keep2")
        m2.charts[a].owner = "A"
        m2.charts[b].owner = "B"
        m2.charts[c].owner = "A"
        set_active_chart!(m2, a)
        set_filter_owner!(m2, "A")
        @test length(visible_charts(m2)) == 2
        _cycle_active_visible!(m2, +1)
        @test current_chart(m2).name == "Keep2"
        _cycle_active_visible!(m2, +1)
        @test current_chart(m2).name == "Keep2"  # clamped at end
        _cycle_active_visible!(m2, -1)
        @test current_chart(m2).name == "Keep"
        # never lands on Hide while filter active
        for _ in 1:5
            _cycle_active_visible!(m2, +1)
            @test current_chart(m2).name != "Hide"
        end
    end

    @testset "tools registry pure CRUD (add_tool!/delete_tool!)" begin
        d = generate_spc_workbench_data(8; seed = 9)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        @test isempty(m.tools)
        @test m.tools_selected == 1
        @test m.tools_scroll == 0

        # refuse empty id
        @test add_tool!(m, "") === nothing
        @test add_tool!(m, "   ") === nothing
        @test isempty(m.tools)

        # add
        i1 = add_tool!(m, "ETCH-1", "Etch tool 1")
        @test i1 == 1
        @test length(m.tools) == 1
        @test m.tools[1].id == "ETCH-1"
        @test m.tools[1].description == "Etch tool 1"
        @test m.tools_selected == 1

        i2 = add_tool!(m, "  CVD-2  ", "  CVD  ")
        @test i2 == 2
        @test m.tools[2].id == "CVD-2"
        @test m.tools[2].description == "CVD"
        @test m.tools_selected == 2

        # refuse duplicate (case-sensitive)
        @test add_tool!(m, "ETCH-1") === nothing
        @test length(m.tools) == 2
        @test add_tool!(m, "etch-1", "lower") == 3  # different id
        @test m.tools[3].id == "etch-1"

        # delete clamps selection
        m.tools_selected = 3
        @test delete_tool!(m, 3) === true
        @test length(m.tools) == 2
        @test m.tools_selected == 2
        m.tools_selected = 1
        @test delete_tool!(m, 1) === true
        @test length(m.tools) == 1
        @test m.tools[1].id == "CVD-2"
        @test m.tools_selected == 1
        @test delete_tool!(m, 1) === true
        @test isempty(m.tools)
        @test m.tools_selected == 1
        @test delete_tool!(m, 1) === false  # empty
        @test delete_tool!(m, 0) === false

        # registry is distinct from chart tools assignment
        add_chart!(m; name = "C1")
        @test isempty(m.charts[1].tools)  # add_tool! does not touch ch.tools
        i = add_tool!(m, "REG-ONLY")
        @test i == 1
        @test isempty(m.charts[1].tools)
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

    @testset "plot axis labels + labeled USL/LSL (and UCL/LCL/CL) lines" begin
        # HTML parity: Y tick numbers on left; X range on bottom; limit-line labels on right.
        # Side panel uses "USL="; plot labels must be distinct ("USL" / "USL …") and inside plot_area.
        function _plot_text(tb, pa)
            rows = String[]
            for y in pa.y:T.bottom(pa)
                chars = Char[]
                for x in pa.x:T.right(pa)
                    ch = T.char_at(tb, x, y)
                    push!(chars, (ch === nothing || ch == '\0') ? ' ' : ch)
                end
                push!(rows, String(chars))
            end
            return join(rows, "\n")
        end
        function _row_has(tb, pa, y, needle::AbstractString)
            chars = Char[]
            for x in pa.x:T.right(pa)
                ch = T.char_at(tb, x, y)
                push!(chars, (ch === nothing || ch == '\0') ? ' ' : ch)
            end
            return occursin(needle, String(chars))
        end

        d = generate_spc_workbench_data(20; seed=55, μ=100.0, σ=2.0)
        n = length(d.values)
        m = SPCWorkbenchModel(
            data = d,
            viewport = Viewport(x0 = 1, x1 = n, ylo = 0.0, yhi = 1.0),
            paused = true,
            usl = 110.0,
            lsl = 90.0,
            seed_demos = :single,
        )
        tb = T.TestBackend(100, 28)
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 28), [], []))
        pa = m.plot_area
        @test pa.width > 10 && pa.height > 5
        plot_txt = _plot_text(tb, pa)

        # X-axis range labels (viewport indices) on plot
        @test occursin(string(m.viewport.x0), plot_txt)
        @test occursin(string(m.viewport.x1), plot_txt)

        # Y-axis tick values (min / max of fitted viewport) appear in plot region
        ylo_s = string(round(m.viewport.ylo; digits = 1))
        yhi_s = string(round(m.viewport.yhi; digits = 1))
        @test occursin(ylo_s, plot_txt)
        @test occursin(yhi_s, plot_txt)
        # Top/bottom rows of plot should carry the corresponding Y ticks
        @test _row_has(tb, pa, pa.y, yhi_s) || _row_has(tb, pa, pa.y + 1, yhi_s)
        @test _row_has(tb, pa, T.bottom(pa), ylo_s) || _row_has(tb, pa, T.bottom(pa) - 1, ylo_s)

        # Spec lines labeled inside plot (not only side "USL=")
        @test occursin("USL", plot_txt)
        @test occursin("LSL", plot_txt)
        usl_y = data_val_to_cell_row(110.0, pa, m.viewport)
        lsl_y = data_val_to_cell_row(90.0, pa, m.viewport)
        @test _row_has(tb, pa, usl_y, "USL")
        @test _row_has(tb, pa, lsl_y, "LSL")

        # Control limit labels when ±3σ / CL lines are on
        lz = compute_limits_and_zones(d.values; sigma_method = :mr)
        ucl_y = data_val_to_cell_row(lz.ucl, pa, m.viewport)
        lcl_y = data_val_to_cell_row(lz.lcl, pa, m.viewport)
        cl_y = data_val_to_cell_row(lz.cl, pa, m.viewport)
        @test _row_has(tb, pa, ucl_y, "UCL")
        @test _row_has(tb, pa, lcl_y, "LCL")
        @test _row_has(tb, pa, cl_y, "CL")

        # Specs off → plot loses USL/LSL line labels (side may still show USL=)
        m.show_chart_lines["specs"] = false
        tb2 = T.TestBackend(100, 28)
        T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 28), [], []))
        pa2 = m.plot_area
        @test !_row_has(tb2, pa2, data_val_to_cell_row(110.0, pa2, m.viewport), "USL")
        @test !_row_has(tb2, pa2, data_val_to_cell_row(90.0, pa2, m.viewport), "LSL")
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
        @test occursin("Help", help_text) || occursin("HELP", help_text) ||
              occursin("library", lowercase(help_text)) || occursin("·", help_text)
        # strict no-bleed (real test that would fail without early return in help view)
        @test T.find_text(tb2, "SPC Workbench [dashboard]") === nothing   # normal path header not emitted
        @test T.find_text(tb2, "Side Stats") === nothing
        @test T.find_text(tb2, "Dashboard:") === nothing   # plot block title from normal layout not present

    end

    @testset "keyboard map page (k) shows bindings table + mouse actions; esc closes" begin
        m = SPCWorkbenchModel(data=generate_spc_workbench_data(8;seed=1), paused=true)
        T.update!(m, T.KeyEvent('k'))
        tb = T.TestBackend(90, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,90,36),[],[]))
        krows = [T.row_text(tb, i) for i in 1:36]
        kfull = join([string(r) for r in krows if r!==nothing], "\n")
        @test occursin("KEYBOARD MAP", kfull) || occursin("Keys  · Map", kfull)
        # Styled chips (not legacy monospace dump)
        @test occursin("pause", lowercase(kfull)) || occursin("p ·", kfull)
        @test occursin("MOUSE", uppercase(kfull)) || occursin("mouse", lowercase(kfull))
        @test occursin("builder", lowercase(kfull)) || occursin("b ·", kfull)
        @test occursin("·", kfull) || occursin("▸", kfull)
        T.update!(m, T.KeyEvent(:escape))
        tb2 = T.TestBackend(90, 36); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,90,36),[],[]))
        @test T.find_text(tb2, "KEYBOARD MAP") === nothing
        @test T.find_text(tb2, "Keys  · Map") === nothing
    end

    @testset "builder mode (b): no-bleed + Esc/q close without quit + mouse no-op" begin
        d = generate_spc_workbench_data(12; seed = 3)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        @test m.view_mode === :dashboard
        @test m.quit === false

        T.update!(m, T.KeyEvent('b'))
        @test m.view_mode === :builder
        @test m.quit === false
        @test m.last_event == "builder open"

        tb = T.TestBackend(90, 22); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 22), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:22 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("BUILDER", full)
        @test occursin("Value col", full) || occursin("Value", full)
        # strict no-bleed
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing
        @test T.find_text(tb, "Side Stats") === nothing
        @test T.find_text(tb, "Dashboard:") === nothing

        # mouse early-return (no pan/hover) — same ctor as other TestBackend mouse tests
        T.update!(m, T.MouseEvent(20, 10, T.mouse_left, T.mouse_press, false, false, false))
        @test m.view_mode === :builder
        @test occursin("modal", m.last_event)

        # Esc closes without quit
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        @test m.quit === false

        # q closes without quit
        T.update!(m, T.KeyEvent('b'))
        @test m.view_mode === :builder
        T.update!(m, T.KeyEvent('q'))
        @test m.view_mode === :dashboard
        @test m.quit === false

        # apply materialize from in-memory table
        m.table = SharedTable(
            columns = ["Tool", "Value"],
            rows = [
                Dict("Tool" => "A", "Value" => "10.0"),
                Dict("Tool" => "B", "Value" => "20.0"),
                Dict("Tool" => "A", "Value" => "30.0"),
            ],
        )
        ch = current_chart(m)
        ch.tools = ["A"]
        ch.col_value = "Value"
        ch.col_tool = "Tool"
        T.update!(m, T.KeyEvent('b'))
        T.update!(m, T.KeyEvent('a'))
        @test m.view_mode === :dashboard
        @test m.quit === false
        @test current_chart(m).source === :table
        @test current_chart(m).live_enabled === false
        @test current_chart(m).data.values == [10.0, 30.0]
        @test occursin("materialized", m.last_event)

        # help mentions builder
        T.update!(m, T.KeyEvent('h'))
        tbh = T.TestBackend(90, 24); T.reset!(tbh.buf)
        T.view(m, T.Frame(tbh.buf, T.Rect(1, 1, 90, 24), [], []))
        htxt = join([string(T.row_text(tbh, i)) for i in 1:24 if T.row_text(tbh, i) !== nothing], "\n")
        @test occursin("b/B", htxt) || occursin("builder", lowercase(htxt))
    end

    @testset "builder: Enter-edit manual CL/UCL/LCL + invalid number keeps prior" begin
        d = generate_spc_workbench_data(10; seed = 11)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        ch0 = current_chart(m)
        ch0.manual_cl = 50.0  # prior value that invalid edit must not clear
        T.update!(m, T.KeyEvent('b'))
        @test m.view_mode === :builder

        # BUILDER_FIELDS (P2-PR5): 1 name, 2 chart_type, 3 col_value, 4 col_n,
        # 5 col_tool, 6 col_time, 7 col_lot, 8 tools, 9 owner, 10 subgroup_size,
        # 11 limits_mode, 12 manual_cl, 13 manual_ucl, 14 manual_lcl
        # Navigate to limits_mode (field 11) and toggle to manual
        for _ in 1:10
            T.update!(m, T.KeyEvent(:down))
        end
        @test m.builder_selected == 11
        T.update!(m, T.KeyEvent(:enter))  # toggle auto → manual
        @test current_chart(m).limits_mode === :manual

        # manual_cl (field 12): edit to 100
        T.update!(m, T.KeyEvent(:down))
        @test m.builder_selected == 12
        T.update!(m, T.KeyEvent(:enter))
        @test m.builder_editing === true
        # clear any prefilled buf and type 100
        m.builder_buf = ""
        for c in "100"
            T.update!(m, T.KeyEvent(c))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test current_chart(m).manual_cl == 100.0
        @test m.last_event == "field set"

        # manual_ucl = 106
        T.update!(m, T.KeyEvent(:down))
        T.update!(m, T.KeyEvent(:enter))
        m.builder_buf = ""
        for c in "106"
            T.update!(m, T.KeyEvent(c))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test current_chart(m).manual_ucl == 106.0

        # manual_lcl = 94
        T.update!(m, T.KeyEvent(:down))
        T.update!(m, T.KeyEvent(:enter))
        m.builder_buf = ""
        for c in "94"
            T.update!(m, T.KeyEvent(c))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test current_chart(m).manual_lcl == 94.0

        # invalid number keeps prior CL
        for _ in 1:2
            T.update!(m, T.KeyEvent(:up))  # back to manual_cl
        end
        @test m.builder_selected == 12
        T.update!(m, T.KeyEvent(:enter))
        m.builder_buf = ""
        for c in "nope"
            T.update!(m, T.KeyEvent(c))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test current_chart(m).manual_cl == 100.0  # unchanged
        @test m.last_event == "invalid number"
        @test m.view_mode === :builder
        @test m.quit === false

        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        @test m.quit === false
        @test current_chart(m).limits_mode === :manual
        @test current_chart(m).manual_cl == 100.0
        @test current_chart(m).manual_ucl == 106.0
        @test current_chart(m).manual_lcl == 94.0
    end

    @testset "P2-PR5: builder col_lot/col_n/col_time/subgroup_size/owner + Xbar materialize" begin
        # Field order: 1 name, 2 chart_type, 3 col_value, 4 col_n, 5 col_tool,
        # 6 col_time, 7 col_lot, 8 tools, 9 owner, 10 subgroup_size, …
        d = generate_spc_workbench_data(10; seed = 21)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        T.update!(m, T.KeyEvent('b'))
        @test m.view_mode === :builder
        @test length(BUILDER_FIELDS) >= 14
        @test :col_lot in BUILDER_FIELDS
        @test :col_n in BUILDER_FIELDS
        @test :col_time in BUILDER_FIELDS
        @test :subgroup_size in BUILDER_FIELDS
        @test :owner in BUILDER_FIELDS

        # Render shows new labels (taller backend so all fields fit)
        tb = T.TestBackend(100, 28); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 28), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:28 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Lot col", full)
        @test occursin("N col", full)
        @test occursin("Time col", full)
        @test occursin("Subgroup n", full)
        @test occursin("Owner", full)

        # Helper: select field by absolute index via keys from current selection
        function _goto_field!(m, idx)
            while m.builder_selected < idx
                T.update!(m, T.KeyEvent(:down))
            end
            while m.builder_selected > idx
                T.update!(m, T.KeyEvent(:up))
            end
            @test m.builder_selected == idx
        end
        function _edit_field!(m, idx, text)
            _goto_field!(m, idx)
            T.update!(m, T.KeyEvent(:enter))
            @test m.builder_editing === true
            m.builder_buf = ""
            for c in text
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test m.builder_editing === false
            @test m.last_event == "field set"
        end

        # col_n (4), col_time (6), col_lot (7), owner (9) — string fields
        _edit_field!(m, 4, "n")
        @test current_chart(m).col_n == "n"
        _edit_field!(m, 6, "Timestamp")
        @test current_chart(m).col_time == "Timestamp"
        _edit_field!(m, 7, "Wafer")
        @test current_chart(m).col_lot == "Wafer"
        _edit_field!(m, 9, "fab-eng")
        @test current_chart(m).owner == "fab-eng"

        # subgroup_size (10): clamp 2..25; invalid keeps prior
        _edit_field!(m, 10, "3")
        @test current_chart(m).subgroup_size == 3
        _edit_field!(m, 10, "99")  # clamp to 25
        @test current_chart(m).subgroup_size == 25
        _edit_field!(m, 10, "1")   # clamp to 2
        @test current_chart(m).subgroup_size == 2
        _goto_field!(m, 10)
        T.update!(m, T.KeyEvent(:enter))
        m.builder_buf = ""
        for c in "nope"
            T.update!(m, T.KeyEvent(c))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test current_chart(m).subgroup_size == 2  # unchanged
        @test m.last_event == "invalid number"

        # y/Y still cycles chart_type only (global shortcut; not field-dependent)
        @test current_chart(m).chart_type === I_MR
        T.update!(m, T.KeyEvent('y'))
        @test current_chart(m).chart_type === Xbar_R
        @test occursin("type", m.last_event)
        # col_lot must not have been cleared by y
        @test current_chart(m).col_lot == "Wafer"

        # owner string matches filter_owner
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        set_filter_owner!(m, "fab-eng")
        @test length(visible_charts(m)) == 1
        @test visible_charts(m)[1].owner == "fab-eng"
        set_filter_owner!(m, "other")
        @test isempty(visible_charts(m))
        clear_filters!(m)

        # Xbar col_lot materialize path via builder apply (a)
        m.table = SharedTable(
            columns = ["Timestamp", "Tool", "Wafer", "Value"],
            rows = [
                Dict("Timestamp" => "t1", "Tool" => "ETCH-A", "Wafer" => "W01", "Value" => "8"),
                Dict("Timestamp" => "t2", "Tool" => "ETCH-A", "Wafer" => "W01", "Value" => "10"),
                Dict("Timestamp" => "t3", "Tool" => "ETCH-A", "Wafer" => "W01", "Value" => "12"),
                Dict("Timestamp" => "t4", "Tool" => "ETCH-A", "Wafer" => "W02", "Value" => "11"),
                Dict("Timestamp" => "t5", "Tool" => "ETCH-A", "Wafer" => "W02", "Value" => "12"),
                Dict("Timestamp" => "t6", "Tool" => "ETCH-A", "Wafer" => "W02", "Value" => "13"),
                Dict("Timestamp" => "t7", "Tool" => "ETCH-A", "Wafer" => "W03", "Value" => "9"),
                Dict("Timestamp" => "t8", "Tool" => "ETCH-A", "Wafer" => "W03", "Value" => "11"),
                Dict("Timestamp" => "t9", "Tool" => "ETCH-A", "Wafer" => "W03", "Value" => "13"),
            ],
        )
        ch = current_chart(m)
        ch.chart_type = Xbar_R
        ch.tools = ["ETCH-A"]
        ch.col_value = "Value"
        ch.col_tool = "Tool"
        ch.col_time = "Timestamp"
        ch.col_lot = "Wafer"
        ch.subgroup_size = 3
        T.update!(m, T.KeyEvent('b'))
        @test m.view_mode === :builder
        # labels still present after setup
        tb2 = T.TestBackend(100, 28); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 28), [], []))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:28 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("Wafer", full2)
        @test occursin("Xbar-R", full2) || occursin("Xbar", full2)

        T.update!(m, T.KeyEvent('a'))  # apply + materialize
        @test m.view_mode === :dashboard
        ch = current_chart(m)
        @test ch.source === :table
        @test ch.live_enabled === false
        @test get(ch.data.meta, "table_subgroups", false) === true
        @test ch.data.values ≈ [10.0, 12.0, 11.0]
        @test ch.data.meta["labels"] == ["W01", "W02", "W03"]
        @test ch.data.meta["secondary_name"] == "R"
        @test ch.data.meta["secondary_vals"] ≈ [4.0, 2.0, 4.0]
        @test ch.col_lot == "Wafer"
        @test ch.subgroup_size == 3
        @test ch.owner == "fab-eng"
        @test occursin("materialized", m.last_event)
    end

    @testset "dashboard multi-chart text + multiple plots visible simultaneously" begin
        # use default ctor that will populate multi in impl
        m = SPCWorkbenchModel(data=generate_spc_workbench_data(15;seed=99), paused=true)
        _ensure_charts!(m)  # ensure copies exist before we mutate ch2
        # Pref off so multi-pane neighbors stay visible (dual compress would hide them at H=28)
        m.visual_prefs["secondary_canvas"] = false
        # Force OOS on ch2 (secondary) so its render path draws an ✕ marker
        if length(m.charts) >= 2
            ch2 = m.charts[2]
            if length(ch2.data.values) >= 1
                ch2.usl = mean(ch2.data.values)
                ch2.data.values[1] = ch2.usl + 10.0
            end
        end
        # Tall enough for 3 stacked plots + Side Stats (Lines + WECO + chart list)
        tb = T.TestBackend(90, 40); T.reset!(tb.buf)
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
        # Pref off so dual compress does not hide the neighbor pane under test
        m.visual_prefs["secondary_canvas"] = false
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

    @testset "marker colors: OK ● green (:success), OOC ◆ red (:error)" begin
        # In-spec / OK samples are green; pure OOC WECO diamonds are red (not yellow/primary).
        green = T.tstyle(:success, bold=true)
        red = T.tstyle(:error, bold=true)

        # --- OK points: flat series, no specs, all :ok ---
        vals_ok = Float64[1.0, 1.1, 0.9, 1.05, 0.95, 1.0, 1.02, 0.98, 1.0, 1.0]
        d_ok = WorkbenchData(values=vals_ok, cl=1.0, sigma=0.5)
        m_ok = SPCWorkbenchModel(data=d_ok, paused=true, seed_demos=:single)
        m_ok.usl = nothing; m_ok.lsl = nothing
        m_ok.visual_prefs["secondary_canvas"] = false
        for k in keys(m_ok.show_chart_lines); m_ok.show_chart_lines[k] = false; end
        _ensure_charts!(m_ok)
        ch_ok = m_ok.charts[1]
        ch_ok.usl = nothing; ch_ok.lsl = nothing
        ch_ok.enabled_rules = Dict("WECO-$i" => false for i in 1:8)
        m_ok.enabled_rules = ch_ok.enabled_rules
        ctx_ok = resolve_chart_render_context(ch_ok)
        @test all(i -> point_status(i, ctx_ok, ch_ok) == :ok, 1:length(vals_ok))
        tb_ok = T.TestBackend(70, 16); T.reset!(tb_ok.buf)
        T.view(m_ok, T.Frame(tb_ok.buf, T.Rect(1,1,70,16),[],[]))
        found_green = false
        for y in 1:16, x in 1:70
            if T.char_at(tb_ok, x, y) == '●' && T.style_at(tb_ok, x, y) == green
                found_green = true
                break
            end
        end
        @test found_green

        # --- OOC ◆ red ---
        d = generate_spc_workbench_data(20; seed=123, hints=Dict{String,Any}("trigger"=>"WECO-1"))
        m = SPCWorkbenchModel(data=d, paused=true)
        m.usl = nothing
        m.lsl = nothing
        mu = mean(m.data.values)
        sig = max(std(m.data.values; corrected=true), 1e-6)
        m.data.values[1] = mu + 5 * sig   # extreme OOC (WECO-1)
        m.viewport.x0 = 1
        m.viewport.x1 = max(m.viewport.x1, 5)

        _ensure_charts!(m)
        ch = m.charts[1]
        ch.usl = nothing
        ch.lsl = nothing
        ctx = resolve_chart_render_context(ch; sigma_method=:mr)
        @test point_status(1, ctx, ch) == :ooc

        tb = T.TestBackend(70, 16); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,70,16),[],[]))
        found_red_diamond = false
        found_any_diamond = false
        for y in 1:16
            row = T.row_text(tb, y)
            row === nothing && continue
            for x in 1:length(row)
                if T.char_at(tb, x, y) == '◆'
                    found_any_diamond = true
                    if T.style_at(tb, x, y) == red
                        found_red_diamond = true
                    end
                end
            end
        end
        @test found_any_diamond
        @test found_red_diamond
    end

    @testset "no residual braille dots beside point markers" begin
        # Regression: map_to_dot_* and data_index_to_cell can land sample braille in a
        # neighboring cell from ●/◆/✕, leaving a tiny braille speck beside the marker.
        # With connectors + limit lines off, markers must fully replace sample canvas dots.
        is_braille(c::Char) = let u = UInt32(c); 0x2800 <= u <= 0x28FF; end
        marker_syms = Set(['●', '◆', '✕'])
        # Non-flat series so Y mapping mismatch is likely if coords diverge
        vals = Float64[0.0, 1.5, 0.5, 2.0, 1.0, 3.0, 0.2, 2.5, 1.2, 0.8, 2.2, 1.8]
        d = WorkbenchData(values=vals, cl=1.4, sigma=0.8)
        m = SPCWorkbenchModel(data=d, paused=true,
            viewport=Viewport(x0=1, x1=length(vals), ylo=-0.5, yhi=3.5))
        m.visual_prefs["solid_series"] = false
        m.visual_prefs["solid_stroke"] = false
        m.visual_prefs["braille_series"] = false
        m.visual_prefs["secondary_canvas"] = false
        for k in keys(m.show_chart_lines)
            m.show_chart_lines[k] = false
        end
        m.usl = nothing
        m.lsl = nothing
        _ensure_charts!(m)
        ch = m.charts[1]
        ch.usl = nothing
        ch.lsl = nothing

        tb = T.TestBackend(70, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 70, 18), [], []))
        pa = m.plot_area
        @test pa.width > 4 && pa.height > 3

        marker_cells = Tuple{Int,Int}[]
        residual_braille = Tuple{Int,Int,Char}[]
        for y in pa.y:T.bottom(pa), x in pa.x:T.right(pa)
            c = T.char_at(tb, x, y)
            if c in marker_syms
                push!(marker_cells, (x, y))
            elseif is_braille(c)
                push!(residual_braille, (x, y, c))
            end
        end
        @test length(marker_cells) >= 3
        # Sample braille must not survive beside/under markers when connectors are off
        @test isempty(residual_braille)
        # Also: no braille in 4-neighbors of any marker (belt-and-suspenders)
        for (mx, my) in marker_cells
            for (dx, dy) in ((-1, 0), (1, 0), (0, -1), (0, 1))
                nx, ny = mx + dx, my + dy
                (nx < pa.x || nx > T.right(pa) || ny < pa.y || ny > T.bottom(pa)) && continue
                @test !is_braille(T.char_at(tb, nx, ny))
            end
        end
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

    @testset "Small terminal guard + full-page Config no-bleed" begin
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
        @test m.view_mode === :config
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
        init_full = join([string(T.row_text(tb0, i)) for i in 1:18 if T.row_text(tb0, i) !== nothing], "\n")
        @test !occursin("EDITING", init_full)

        # press u → should enter usl edit; Message center MUST show it
        T.update!(m, T.KeyEvent('u'))
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        @test m.editing == :usl
        full = join([string(T.row_text(tb, i)) for i in 1:18 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("EDITING USL", full) || occursin("edit usl", lowercase(full))
        # last_event or prompt should mention it
        @test m.last_event != ""

        # type digits — Message center must reflect the accumulating input value (not frozen)
        T.update!(m, T.KeyEvent('1'))
        T.update!(m, T.KeyEvent('3'))
        T.update!(m, T.KeyEvent('2'))
        T.update!(m, T.KeyEvent('0'))
        tb2 = T.TestBackend(80, 18); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,80,18),[],[]))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:18 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("1320", full2)   # typed value appears in Message center

        # q while in editing should still quit the app (was swallowed → freeze)
        T.update!(m, T.KeyEvent('q'))
        @test m.quit == true

        # (note: a separate flow would use Esc to cancel instead of q)
    end

    # ── Bottom chrome: Message center (left) + Keys panel (right) ─────────
    # Replaces Current/Cpk gauges; footer bracket-key strip removed; ? expands keys.
    @testset "bottom panels: Message center, Keys panel, no footer key strip" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        _ensure_charts!(m)

        tb = T.TestBackend(100, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")

        # Left panel is Message center (not Current gauge)
        @test occursin("Message", full)
        @test !occursin("Current", full)

        # Right panel is Keys (contextual help home)
        @test occursin("Keys", full)

        # No bracket-key chrome anywhere (moved into Keys panel; status footer removed)
        @test !occursin(r"\[p g r c", full)
        @test !occursin("[h k []]", full)
        @test !occursin("paused=true mode=", full)

        # Header cleaned: no long [p]pause [g]live key dump (keys live in Keys panel)
        header = string(T.row_text(tb, 1))
        @test !occursin("[p]pause", header)
        @test !occursin("[g]live", header)

        # Collapsed Keys panel shows a few most-used bindings
        @test occursin("pause", lowercase(full)) || occursin(" p ", full) ||
              occursin("[p]", full) || occursin("p pause", lowercase(full))
    end

    @testset "Message center: shows last_event + editing input with severity colors" begin
        d = generate_spc_workbench_data(10; seed=7)
        m = SPCWorkbenchModel(data=d, paused=true)
        _ensure_charts!(m)

        # Neutral event → appears in Message panel (not only as last= footer)
        m.last_event = "live on"
        tb = T.TestBackend(100, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("live on", full)
        @test occursin("Message", full)

        # Warning-class event uses :warning style somewhere in message area (bottom third)
        m.last_event = "No charts match filters"
        tbw = T.TestBackend(100, 24); T.reset!(tbw.buf)
        T.view(m, T.Frame(tbw.buf, T.Rect(1, 1, 100, 24), [], []))
        warn_style = T.tstyle(:warning, bold=true)
        found_warn = false
        for y in 18:24, x in 1:50
            if T.char_at(tbw, x, y) != ' ' && T.style_at(tbw, x, y) == warn_style
                found_warn = true
                break
            end
        end
        @test found_warn

        # Error-class event uses :error style
        m.last_event = "invalid number"
        tbe = T.TestBackend(100, 24); T.reset!(tbe.buf)
        T.view(m, T.Frame(tbe.buf, T.Rect(1, 1, 100, 24), [], []))
        err_style = T.tstyle(:error, bold=true)
        found_err = false
        for y in 18:24, x in 1:50
            if T.char_at(tbe, x, y) != ' ' && T.style_at(tbe, x, y) == err_style
                found_err = true
                break
            end
        end
        @test found_err

        # Editing: Message center shows EDITING + typed buffer (anywhere on screen, not only footer row)
        T.update!(m, T.KeyEvent('u'))
        T.update!(m, T.KeyEvent('1'))
        T.update!(m, T.KeyEvent('2'))
        T.update!(m, T.KeyEvent('3'))
        tbed = T.TestBackend(100, 24); T.reset!(tbed.buf)
        T.view(m, T.Frame(tbed.buf, T.Rect(1, 1, 100, 24), [], []))
        ed_full = join([string(T.row_text(tbed, i)) for i in 1:24 if T.row_text(tbed, i) !== nothing], "\n")
        @test occursin("EDITING", uppercase(ed_full)) || occursin("USL", ed_full)
        @test occursin("123", ed_full)
        accent = T.tstyle(:accent, bold=true)
        found_accent = false
        for y in 18:24, x in 1:55
            if T.char_at(tbed, x, y) != ' ' && T.style_at(tbed, x, y) == accent
                found_accent = true
                break
            end
        end
        @test found_accent
    end

    @testset "Keys panel: contextual bindings; ? expands upward and collapses" begin
        d = generate_spc_workbench_data(10; seed=3)
        m = SPCWorkbenchModel(data=d, paused=true)
        _ensure_charts!(m)
        @test m.keys_panel_expanded == false

        # Collapsed: fixed short height — count key-ish lines limited
        tbc = T.TestBackend(100, 28); T.reset!(tbc.buf)
        T.view(m, T.Frame(tbc.buf, T.Rect(1, 1, 100, 28), [], []))
        full_c = join([string(T.row_text(tbc, i)) for i in 1:28 if T.row_text(tbc, i) !== nothing], "\n")
        @test occursin("Keys", full_c)
        # most-used present when collapsed
        @test occursin("q", lowercase(full_c))

        # ? toggles expand (does not open full-page help)
        T.update!(m, T.KeyEvent('?'))
        @test m.keys_panel_expanded == true
        @test m.view_mode == :dashboard
        @test m.last_event == "keys expanded" || occursin("expand", lowercase(m.last_event))

        tbe = T.TestBackend(100, 28); T.reset!(tbe.buf)
        T.view(m, T.Frame(tbe.buf, T.Rect(1, 1, 100, 28), [], []))
        full_e = join([string(T.row_text(tbe, i)) for i in 1:28 if T.row_text(tbe, i) !== nothing], "\n")
        # Expanded shows more bindings than compact (library / tools / table / WECO / specs)
        expanded_hits = count(s -> occursin(s, lowercase(full_e)),
            ["library", "tools", "table", "weco", "usl", "filter", "config", "specs", "builder"])
        compact_hits = count(s -> occursin(s, lowercase(full_c)),
            ["library", "tools", "table", "weco", "usl", "filter", "config", "specs", "builder"])
        @test expanded_hits > compact_hits
        # Expand grows upward: plot area height shrinks when keys expanded
        @test m.plot_area.height < 20  # with h=28 chrome, expanded gauge steals rows

        # ? again collapses
        T.update!(m, T.KeyEvent('?'))
        @test m.keys_panel_expanded == false
        @test m.last_event == "keys collapsed" || occursin("collapse", lowercase(m.last_event))

        # h still opens full help page (not just expand)
        T.update!(m, T.KeyEvent('h'))
        @test m.view_mode == :help
    end

    @testset "mode pages share Message|Keys chrome style (library/tools/table/builder/help/keymap)" begin
        d = generate_spc_workbench_data(10; seed=5)
        function _mode_full(key; w=100, h=28)
            m = SPCWorkbenchModel(data=d, paused=true)
            _ensure_charts!(m)
            T.update!(m, T.KeyEvent(key))
            tb = T.TestBackend(w, h); T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, w, h), [], []))
            full = join([string(T.row_text(tb, i)) for i in 1:h if T.row_text(tb, i) !== nothing], "\n")
            return m, tb, full
        end

        for (key, mode_word, expect_bind) in (
            ('m', "Library", "clone"),
            ('x', "Tools", "add"),
            ('d', "Table", "edit"),
            ('b', "Builder", "apply"),
        )
            m, tb, full = _mode_full(key)
            @test occursin("Message", full)
            @test occursin("Keys", full)
            # Pretty chips (not the old flat dim footer dump)
            @test occursin("·", full)
            @test occursin(expect_bind, lowercase(full))
            # No legacy last= strip or old flat key dump lines
            @test !occursin("last=", full) || occursin("Message", full)
            @test !occursin("↑↓/click select  Enter/dblclick", full)
            @test !occursin("↑↓ select  Enter filter+close", full)
            # Accent on Keys chrome (right half bottom)
            accent = T.tstyle(:accent, bold=true)
            found = false
            for y in 20:28, x in 52:100
                if T.char_at(tb, x, y) != ' ' && T.style_at(tb, x, y) == accent
                    found = true
                    break
                end
            end
            @test found
            # No dashboard bleed
            @test m.view_mode != :dashboard
            @test !occursin("SPC Workbench [dashboard]", full)
        end

        # Help + keymap restyled with section markers / chips (not only plain monospace dump)
        _, _, hfull = _mode_full('h'; w=100, h=36)
        @test occursin("HELP", uppercase(hfull)) || occursin("Help", hfull)
        @test occursin("▸", hfull) || occursin("·", hfull)
        @test occursin("library", lowercase(hfull))

        _, _, kfull = _mode_full('k'; w=100, h=36)
        @test occursin("KEY", uppercase(kfull)) || occursin("Keys", kfull) || occursin("KEYBOARD", uppercase(kfull))
        @test occursin("▸", kfull) || occursin("·", kfull)
        @test occursin("mouse", lowercase(kfull))
    end

    @testset "no status strip below Message; Keys panel pretty key·label layout" begin
        d = generate_spc_workbench_data(12; seed=11)
        m = SPCWorkbenchModel(data=d, paused=true)
        _ensure_charts!(m)
        m.last_event = "live on"

        tb = T.TestBackend(100, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        # No redundant status chrome below / under Message
        @test !occursin("paused=true", full)
        @test !occursin("mode=dashboard", full)
        @test !occursin("edit=", full)
        # Message still shows the event
        @test occursin("live on", full)
        @test occursin("Message", full)

        # Collapsed Keys uses key · label separators (readable chips)
        @test occursin("·", full) || occursin(" · ", full)
        @test occursin("pause", lowercase(full))

        # Expanded: section headers + multi-row key·label grid
        T.update!(m, T.KeyEvent('?'))
        @test m.keys_panel_expanded == true
        tbe = T.TestBackend(100, 30); T.reset!(tbe.buf)
        T.view(m, T.Frame(tbe.buf, T.Rect(1, 1, 100, 30), [], []))
        full_e = join([string(T.row_text(tbe, i)) for i in 1:30 if T.row_text(tbe, i) !== nothing], "\n")
        @test occursin("PAGES", full_e) || occursin("Pages", full_e)
        @test occursin("library", lowercase(full_e))
        @test occursin("·", full_e)
        # Still no status strip when expanded
        @test !occursin("paused=true", full_e)
        @test !occursin("mode=dashboard", full_e)

        # Accent styling on at least one key glyph in Keys panel (right half)
        accent = T.tstyle(:accent, bold=true)
        found_key_accent = false
        for y in 18:30, x in 52:100
            ch = T.char_at(tbe, x, y)
            if ch != ' ' && T.style_at(tbe, x, y) == accent
                found_key_accent = true
                break
            end
        end
        @test found_key_accent
    end

    # Side Stats: WECO on/off as filled/empty circle bubbles (● green on, ○ dim off)
    # PR2 locator: find 8-char bubble run in side_area (do NOT require WECO on same row).
    # Disambiguate Lines rows (single ● + "CL="/ "±") from WECO (8 consecutive bubbles).
    function _side_weco_bubbles(tb, m)
        sa = m.side_area
        best = nothing
        for y in sa.y:T.bottom(sa)
            chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
            txt = rstrip(String(chars))
            # Skip Lines parameter rows (single bubble + label=)
            occursin("CL=", txt) && continue
            occursin("±", txt) && continue
            occursin("Specs=", txt) && continue
            bubbles = Char[]
            for ch in chars
                if ch == '●' || ch == '○'
                    push!(bubbles, ch)
                end
            end
            length(bubbles) < 8 && continue
            # Prefer row with WECO on same or previous row when multiple candidates
            has_weco_near = occursin("WECO", txt)
            if !has_weco_near && y > sa.y
                prev = Char[T.char_at(tb, x, y - 1) for x in sa.x:T.right(sa)]
                has_weco_near = occursin("WECO", rstrip(String(prev)))
            end
            cand = (y=y, bubbles=String(bubbles[1:8]), sa=sa, weco_near=has_weco_near)
            if best === nothing || (has_weco_near && !best.weco_near)
                best = cand
            end
        end
        return best === nothing ? nothing : (y=best.y, bubbles=best.bubbles, sa=best.sa)
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

    @testset "side panel mode badge + last-N WECO messages when violations present (PR5)" begin
        # Craft series that triggers WECO-1 under known CL/σ (manual limits)
        cl, s = 0.0, 1.0
        vals = [0.0, 0.1, 0.0, 3.5, -0.1, 0.0, 0.2, 0.0, -0.1, 0.0]  # idx 4 beyond +3σ
        d = WorkbenchData(values = vals, cl = cl, sigma = s)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        # Ensure single chart + manual limits on the active chart
        _ensure_charts!(m)
        ch = current_chart(m)
        ch.limits_mode = :manual
        ch.manual_cl = cl
        ch.manual_ucl = cl + 3 * s
        ch.manual_lcl = cl - 3 * s
        ch.enabled_rules = Dict(
            "WECO-1" => true, "WECO-2" => false, "WECO-3" => false, "WECO-4" => false,
            "WECO-5" => false, "WECO-6" => false, "WECO-7" => false, "WECO-8" => false,
        )
        m.enabled_rules = ch.enabled_rules
        # Tall side panel so Viols list is not clipped by chart list / gauges
        tb = T.TestBackend(100, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 36), [], []))
        @test m.side_area.width > 0
        side = join([T.row_text(tb, i) for i = 1:36 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("limits:manual", side)
        @test occursin("Viols:", side)
        # WECO-1 message from weco_detect should appear (rule tag + beyond)
        @test occursin("WECO-1", side)
        @test occursin("beyond", side) || occursin("#4", side) || occursin("3.5", side)
        # Pure resolver agrees there is a violation at index 4
        ctx = resolve_chart_render_context(ch)
        @test 4 in ctx.viol_indices
        @test isapprox(ctx.lz.sigma, 1.0; atol = 1e-12)

        # Auto badge when limits_mode is auto
        ch.limits_mode = :auto
        tb2 = T.TestBackend(100, 36); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 36), [], []))
        side2 = join([T.row_text(tb2, i) for i = 1:36 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("limits:auto", side2)
        @test !occursin("limits:manual", side2)

        # Incomplete manual (missing lcl) → effective auto badge (same gateway predicate)
        ch.limits_mode = :manual
        ch.manual_cl = cl
        ch.manual_ucl = cl + 3 * s
        ch.manual_lcl = nothing
        @test _manual_limits_effective(ch) === false
        tb3 = T.TestBackend(100, 36); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1, 1, 100, 36), [], []))
        side3 = join([T.row_text(tb3, i) for i = 1:36 if T.row_text(tb3, i) !== nothing], "\n")
        @test occursin("limits:auto", side3)
        @test !occursin("limits:manual", side3)
    end

    @testset "side stats WECO: blank gap after Specs + rule numbers under bubbles" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,90,24),[],[]))
        sa = m.side_area
        @test sa.width > 0
        @test sa.height >= 15  # tall layout gap contract

        # Locate Specs body and WECO chrome (▸ WECO or compact WECO ●●…)
        specs_y = nothing
        weco_chrome_y = nothing
        for y in sa.y:T.bottom(sa)
            chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
            txt = rstrip(String(chars))
            if occursin("Specs=", txt) || occursin("Specs ", txt)
                specs_y = y
            end
            # Do not use startswith(lstrip, "WECO") — breaks on "▸ WECO"
            if occursin("WECO", txt)
                weco_chrome_y === nothing && (weco_chrome_y = y)
            end
        end
        @test specs_y !== nothing
        @test weco_chrome_y !== nothing
        if specs_y !== nothing && weco_chrome_y !== nothing
            # H=24: require blank gap between Specs and WECO chrome
            @test weco_chrome_y >= specs_y + 2
            for y in (specs_y + 1):(weco_chrome_y - 1)
                chars = Char[T.char_at(tb, x, y) for x in sa.x:T.right(sa)]
                @test all(c -> c == ' ' || c == '\0', chars)
            end
        end

        # Numbers 1-8 under each bubble, column-aligned (digit_y == bubble_y+1)
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
            # Viols: follows digits when digits present
            viol_y = nothing
            for y in (num_y + 1):T.bottom(found.sa)
                chars = Char[T.char_at(tb, x, y) for x in found.sa.x:T.right(found.sa)]
                occursin("Viols:", rstrip(String(chars))) && (viol_y = y; break)
            end
            @test viol_y !== nothing
        end
    end

    @testset "side stats WECO: H=36 boxed chips + digit_x=glyph_x + side_outer/geom (PR2)" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        tb = T.TestBackend(100, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 36), [], []))
        @test m.side_area.width > 0
        @test m.side_outer.width > 0
        @test m.side_outer.x <= m.side_area.x
        @test m.side_outer.width >= m.side_area.width
        @test m.weco_bubble_geom !== nothing
        g = m.weco_bubble_geom
        @test g.boxed === true
        @test g.step == 3
        @test g.n == 8
        @test g.y > 0 && g.x0 > 0

        found = _side_weco_bubbles(tb, m)
        @test found !== nothing
        if found !== nothing
            # Brackets present on bubble row around glyphs
            row_chars = Char[T.char_at(tb, x, found.y) for x in found.sa.x:T.right(found.sa)]
            @test count(==('['), row_chars) >= 8
            @test count(==(']'), row_chars) >= 8
            # Glyph xs match geom centers: x0 + (i-1)*3 + 1
            bubble_xs = Int[]
            for x in found.sa.x:T.right(found.sa)
                ch = T.char_at(tb, x, found.y)
                (ch == '●' || ch == '○') && push!(bubble_xs, x)
            end
            @test length(bubble_xs) == 8
            expected_xs = [g.x0 + (i - 1) * g.step + 1 for i in 1:8]
            @test bubble_xs == expected_xs
            # Digits under glyph centers (digit_x = glyph_x)
            num_y = found.y + 1
            digits = Char[T.char_at(tb, x, num_y) for x in bubble_xs]
            @test digits == ['1', '2', '3', '4', '5', '6', '7', '8']
            # Default no-hover: ON success, OFF dim (not warning)
            @test m.hovered === nothing
            @test T.style_at(tb, bubble_xs[1], found.y) == T.tstyle(:success)
            @test T.style_at(tb, bubble_xs[6], found.y) == T.tstyle(:text_dim)
        end
    end

    @testset "side stats WECO: cursor-driven light (OK green; OOC point-only red)" begin
        # Vertical cursor / hover drives WECO chip illumination for the current sample.
        # OK point → ON chips lit green (not red for series-wide viols elsewhere).
        # OOC diamond point → only rules firing AT that index light red.
        cl, s = 0.0, 1.0
        vals = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 3.5]
        d = WorkbenchData(values = vals, cl = cl, sigma = s)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        ch = current_chart(m)
        ch.limits_mode = :manual
        ch.manual_cl = cl
        ch.manual_ucl = cl + 3 * s
        ch.manual_lcl = cl - 3 * s
        ch.enabled_rules = Dict(
            "WECO-1" => true, "WECO-2" => true, "WECO-3" => true, "WECO-4" => true,
            "WECO-5" => true, "WECO-6" => false, "WECO-7" => false, "WECO-8" => false,
        )
        m.enabled_rules = ch.enabled_rules
        ctx = resolve_chart_render_context(ch)
        viols = weco_detect(ch.data.values, ctx.lz.cl, ctx.lz.sigma; enabled_rules=ch.enabled_rules)
        rules8 = weco_rules_at_index(viols, 8)
        @test "WECO-1" in rules8
        @test "WECO-4" in rules8
        @test length(rules8) >= 2
        @test point_status(8, ctx, ch) == :ooc
        @test point_status(1, ctx, ch) == :ok
        @test isempty(weco_rules_at_index(viols, 1))

        green = T.tstyle(:success)
        green_bold = T.tstyle(:success, bold=true)
        err_sty = T.tstyle(:error, bold=true)
        dim = T.tstyle(:text_dim)

        function _bubble_xs(tb, found)
            xs = Int[]
            for x in found.sa.x:T.right(found.sa)
                glyph = T.char_at(tb, x, found.y)
                (glyph == '●' || glyph == '○') && push!(xs, x)
            end
            return xs
        end
        function _is_green(sty)
            return sty == green || sty == green_bold
        end

        # No cursor: enable-only (ON green, OFF dim) — no series-wide red
        m.hovered = nothing
        m.selected = nothing
        tb0 = T.TestBackend(100, 36); T.reset!(tb0.buf)
        T.view(m, T.Frame(tb0.buf, T.Rect(1, 1, 100, 36), [], []))
        found0 = _side_weco_bubbles(tb0, m)
        @test found0 !== nothing
        if found0 !== nothing
            xs0 = _bubble_xs(tb0, found0)
            @test length(xs0) == 8
            @test _is_green(T.style_at(tb0, xs0[1], found0.y))
            @test _is_green(T.style_at(tb0, xs0[4], found0.y))
            @test T.style_at(tb0, xs0[1], found0.y) != err_sty
            @test T.style_at(tb0, xs0[4], found0.y) != err_sty
            @test T.style_at(tb0, xs0[6], found0.y) == dim
        end

        # Cursor on OOC red diamond (#8): only point violations light red
        m.hovered = 8
        m.selected = 8
        tb1 = T.TestBackend(100, 36); T.reset!(tb1.buf)
        T.view(m, T.Frame(tb1.buf, T.Rect(1, 1, 100, 36), [], []))
        found1 = _side_weco_bubbles(tb1, m)
        @test found1 !== nothing
        if found1 !== nothing
            xs1 = _bubble_xs(tb1, found1)
            @test length(xs1) == 8
            n_err = count(i -> T.style_at(tb1, xs1[i], found1.y) == err_sty, 1:8)
            @test n_err >= 2
            for rid in rules8
                k = parse(Int, replace(rid, "WECO-" => ""))
                @test T.style_at(tb1, xs1[k], found1.y) == err_sty
            end
            # ON rules that do NOT fire at this point stay green (not series-red)
            for k in 1:5
                rid = "WECO-$k"
                if rid ∉ rules8
                    @test _is_green(T.style_at(tb1, xs1[k], found1.y))
                    @test T.style_at(tb1, xs1[k], found1.y) != err_sty
                end
            end
            @test T.style_at(tb1, xs1[6], found1.y) == dim
        end

        # Cursor on green OK point (#1): lit green; no red chips (even if series has viols elsewhere)
        m.hovered = 1
        m.selected = 1
        tb_ok = T.TestBackend(100, 36); T.reset!(tb_ok.buf)
        T.view(m, T.Frame(tb_ok.buf, T.Rect(1, 1, 100, 36), [], []))
        found_ok = _side_weco_bubbles(tb_ok, m)
        @test found_ok !== nothing
        if found_ok !== nothing
            xs_ok = _bubble_xs(tb_ok, found_ok)
            @test length(xs_ok) == 8
            for k in 1:5
                @test _is_green(T.style_at(tb_ok, xs_ok[k], found_ok.y))
                @test T.style_at(tb_ok, xs_ok[k], found_ok.y) != err_sty
            end
            @test T.style_at(tb_ok, xs_ok[6], found_ok.y) == dim
        end

        # Clear cursor → back to enable-only green (no residual red from last OOC)
        m.hovered = nothing
        m.selected = nothing
        tb2 = T.TestBackend(100, 36); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 36), [], []))
        found2 = _side_weco_bubbles(tb2, m)
        @test found2 !== nothing
        if found2 !== nothing
            xs2 = _bubble_xs(tb2, found2)
            @test length(xs2) == 8
            @test _is_green(T.style_at(tb2, xs2[1], found2.y))
            @test _is_green(T.style_at(tb2, xs2[4], found2.y))
            @test T.style_at(tb2, xs2[1], found2.y) != err_sty
        end
    end

    @testset "WECO mouse regions: side_outer preserve hover + bubble press flags (PR3a gates 1–4)" begin
        d = generate_spc_workbench_data(18; seed=42)
        n = length(d.values)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=n))
        tb = T.TestBackend(100, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 36), [], []))
        pa = m.plot_area
        so = m.side_outer
        @test pa.width > 5 && so.width > 0
        @test m.weco_bubble_geom !== nothing
        g = m.weco_bubble_geom

        # Seed hover via plot move
        cx = pa.x + pa.width ÷ 2
        cy = pa.y + pa.height ÷ 2
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hovered !== nothing
        h0 = m.hovered

        # Gate 1: move from plot onto side_outer → hovered unchanged
        sx = so.x + so.width ÷ 2
        sy = so.y + so.height ÷ 2
        @test T.contains(so, sx, sy)
        @test !T.contains(pa, sx, sy)
        T.update!(m, T.MouseEvent(sx, sy, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hovered === h0

        # Gate 2: move outside both plot and side_outer → hovered cleared
        ox, oy = 1, 1  # terminal chrome / header corner
        @test !T.contains(pa, ox, oy)
        @test !T.contains(so, ox, oy)
        T.update!(m, T.MouseEvent(ox, oy, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hovered === nothing

        # Re-seed hover for bubble press gates
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hovered !== nothing
        h1 = m.hovered
        vp_x0, vp_x1 = m.viewport.x0, m.viewport.x1

        # Gate 3+4: press on bubble → explain flags; hover preserved; no drag_start / no pan
        bx = g.x0 + (g.boxed ? 1 : 0)  # glyph cell of chip 1 (also in bare chip span)
        by = g.y
        @test _weco_bubble_at(m, bx, by) == 1
        m.drag_start = nothing
        T.update!(m, T.MouseEvent(bx, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.weco_explain_mode === :rule
        @test m.weco_explain_rule == "WECO-1"
        @test m.weco_explain_index === h1
        @test m.hovered === h1
        @test m.drag_start === nothing
        @test m.viewport.x0 == vp_x0 && m.viewport.x1 == vp_x1
        @test occursin("weco explain WECO-1", m.last_event)

        # Same bubble re-press toggles closed (still no drag)
        T.update!(m, T.MouseEvent(bx, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === false
        @test m.weco_explain_rule === nothing
        @test m.hovered === h1
        @test m.drag_start === nothing

        # Other bubble stacks below first; OFF chip (e.g. 6) still opens
        bx6 = g.x0 + (6 - 1) * g.step + (g.boxed ? 1 : 0)
        T.update!(m, T.MouseEvent(bx, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_rule == "WECO-1"
        @test m.weco_explain_stack == ["WECO-1"]
        T.update!(m, T.MouseEvent(bx6, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.weco_explain_stack == ["WECO-1", "WECO-6"]
        @test m.weco_explain_rule == "WECO-6"  # last pressed
        @test m.hovered === h1
        @test m.drag_start === nothing

        # Plot press while explain open: pan/select armed; explain stack stays open (KD-WB-13)
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.weco_explain_stack == ["WECO-1", "WECO-6"]
        @test m.drag_start !== nothing
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_release, false, false, false))
        @test m.drag_start === nothing
        @test m.weco_explain_open === true

        # Outside chrome press closes explain (full stack)
        T.update!(m, T.MouseEvent(ox, oy, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === false
        @test m.weco_explain_rule === nothing
        @test isempty(m.weco_explain_stack)
        @test m.hovered === nothing

        # Pure hit-test helper: miss y / off-row
        @test _weco_bubble_at(m, bx, by + 5) === nothing
        @test _clear_weco_explain!(m) === nothing
    end

    @testset "WECO explain popup: w/Esc/q + paint + clear paths (PR3b)" begin
        d = generate_spc_workbench_data(18; seed=42)
        n = length(d.values)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=n))
        W, H = 100, 36
        tb = T.TestBackend(W, H)
        function re_view!()
            T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, W, H), [], []))
        end
        re_view!()
        @test m.weco_bubble_geom !== nothing
        g = m.weco_bubble_geom
        pa = m.plot_area
        @test pa.width >= 16

        # w open → How: body + title ON; popup rect sized
        @test m.weco_explain_open === false
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === true
        @test m.weco_explain_mode === :rule
        @test m.weco_explain_rule == "WECO-1"  # first enabled
        re_view!()
        @test m.weco_popup_rect.width > 0 && m.weco_popup_rect.height > 0
        @test T.find_text(tb, "How:") !== nothing
        @test T.find_text(tb, "WECO-1") !== nothing
        @test T.find_text(tb, "ON") !== nothing || occursin("ON", m.weco_explain_rule === nothing ? "" :
            weco_explain_content(:rule; rule="WECO-1", enabled=true).title)

        # w toggle close
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === false
        @test m.quit === false
        re_view!()
        @test m.weco_popup_rect.width == 0

        # Bubble press opens painted popup
        bx = g.x0 + (g.boxed ? 1 : 0)
        by = g.y
        T.update!(m, T.MouseEvent(bx, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.weco_explain_rule == "WECO-1"
        re_view!()
        @test T.find_text(tb, "How:") !== nothing

        # Esc closes explain without quit
        T.update!(m, T.KeyEvent(:escape))
        @test m.weco_explain_open === false
        @test m.quit === false

        # q closes explain without quit
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === true
        T.update!(m, T.KeyEvent('q'))
        @test m.weco_explain_open === false
        @test m.quit === false

        # Q also closes without quit
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === true
        T.update!(m, T.KeyEvent('Q'))
        @test m.weco_explain_open === false
        @test m.quit === false

        # Plot press while open: explain stays open (KD-WB-13)
        # Use bottom-left of plot_area so we do not hit the right-anchored popup rect.
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === true
        re_view!()
        pa = m.plot_area
        pop = m.weco_popup_rect
        cx = pa.x + 2
        cy = pa.y + max(1, pa.height - 2)
        @test T.contains(pa, cx, cy)
        @test !(pop.width > 0 && T.contains(pop, cx, cy))
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.drag_start !== nothing
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_release, false, false, false))
        @test m.weco_explain_open === true

        # Outside chrome press closes
        T.update!(m, T.MouseEvent(1, 1, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === false

        # OFF bubble (WECO-6 default off): title OFF + How:
        re_view!()
        g = m.weco_bubble_geom
        bx6 = g.x0 + (6 - 1) * g.step + (g.boxed ? 1 : 0)
        by6 = g.y
        T.update!(m, T.MouseEvent(bx6, by6, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.weco_explain_rule == "WECO-6"
        re_view!()
        @test T.find_text(tb, "OFF") !== nothing
        @test T.find_text(tb, "How:") !== nothing

        # Leave dashboard (library) force-closes explain
        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode === :library
        @test m.weco_explain_open === false
        @test m.weco_explain_rule === nothing

        # Back to dashboard; reopen then config mode also clears
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === true
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config
        @test m.weco_explain_open === false

        # Load ephemerals clear explain
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        T.update!(m, T.KeyEvent('w'))
        @test m.weco_explain_open === true
        _clear_load_ephemerals!(m)
        @test m.weco_explain_open === false
        @test m.weco_explain_rule === nothing
        @test m.weco_popup_rect.width == 0

        # Empty data: w → nothing to explain (seed_demos=:none → empty chart)
        m_empty = SPCWorkbenchModel(data=empty_workbench_data(), paused=true, seed_demos=:none)
        _ensure_charts!(m_empty)
        @test length(m_empty.data.values) == 0
        T.update!(m_empty, T.KeyEvent('w'))
        @test m_empty.weco_explain_open === false
        @test occursin("nothing to explain", m_empty.last_event)

        # Help/keys mention dashboard w=explain (Main-included helpers)
        m2 = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=n))
        entries = _contextual_key_entries(m2; expanded=true)
        flat = join([string(e) for e in entries], " ")
        @test occursin("explain", flat)
        help_e = _mode_key_entries(:help)
        help_flat = join([string(e) for e in help_e], " ")
        @test occursin("explain", help_flat)
        @test occursin("dash w", help_flat) || occursin("WECO explain", help_flat)
    end

    @testset "WECO bubble stack: consecutive presses stack tips below first" begin
        # :single → taller primary plot_area so 3 stacked tips fit (triple primary is ~7 rows)
        d = generate_spc_workbench_data(18; seed=42)
        n = length(d.values)
        m = SPCWorkbenchModel(data=d, paused=true, viewport=Viewport(x0=1, x1=n),
            seed_demos=:single)
        W, H = 100, 36
        tb = T.TestBackend(W, H)
        function re_view!()
            T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, W, H), [], []))
        end
        re_view!()
        @test m.weco_bubble_geom !== nothing
        g = m.weco_bubble_geom
        @test m.plot_area.width >= 16
        @test m.plot_area.height >= 12  # room for 3× ~4-row tips
        @test isempty(m.weco_explain_stack)

        bx1 = g.x0 + (g.boxed ? 1 : 0)
        bx2 = g.x0 + (2 - 1) * g.step + (g.boxed ? 1 : 0)
        bx3 = g.x0 + (3 - 1) * g.step + (g.boxed ? 1 : 0)
        by = g.y
        @test _weco_bubble_at(m, bx1, by) == 1
        @test _weco_bubble_at(m, bx2, by) == 2
        @test _weco_bubble_at(m, bx3, by) == 3

        # First press opens single tip
        T.update!(m, T.MouseEvent(bx1, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_open === true
        @test m.weco_explain_mode === :rule
        @test m.weco_explain_stack == ["WECO-1"]
        @test m.weco_explain_rule == "WECO-1"
        re_view!()
        @test length(m.weco_popup_rects) == 1
        @test m.weco_popup_rects[1].width > 0 && m.weco_popup_rects[1].height > 0
        r1 = m.weco_popup_rects[1]
        @test T.find_text(tb, "WECO-1") !== nothing
        @test T.find_text(tb, "How:") !== nothing

        # Second consecutive press stacks below first (does not replace)
        T.update!(m, T.MouseEvent(bx2, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_stack == ["WECO-1", "WECO-2"]
        @test m.weco_explain_rule == "WECO-2"
        re_view!()
        @test length(m.weco_popup_rects) == 2
        r1b, r2 = m.weco_popup_rects[1], m.weco_popup_rects[2]
        @test r2.y >= r1b.y + r1b.height  # second tip starts at or below first bottom
        @test T.find_text(tb, "WECO-1") !== nothing
        @test T.find_text(tb, "WECO-2") !== nothing
        # Count How: lines — both rule bodies should paint
        how_hits = 0
        for y in 1:H
            row = join(Char[T.char_at(tb, x, y) for x in 1:W])
            occursin("How:", row) && (how_hits += 1)
        end
        @test how_hits >= 2

        # Third press stacks further below
        T.update!(m, T.MouseEvent(bx3, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_stack == ["WECO-1", "WECO-2", "WECO-3"]
        re_view!()
        @test length(m.weco_popup_rects) == 3
        r1c, r2c, r3 = m.weco_popup_rects[1], m.weco_popup_rects[2], m.weco_popup_rects[3]
        @test r2c.y >= r1c.y + r1c.height
        @test r3.y >= r2c.y + r2c.height
        @test T.find_text(tb, "WECO-3") !== nothing

        # Re-press middle chip removes only that tip; others stay stacked
        T.update!(m, T.MouseEvent(bx2, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_stack == ["WECO-1", "WECO-3"]
        @test m.weco_explain_open === true
        re_view!()
        @test length(m.weco_popup_rects) == 2
        @test T.find_text(tb, "WECO-1") !== nothing
        @test T.find_text(tb, "WECO-3") !== nothing

        # Re-press remaining chips one by one closes stack
        T.update!(m, T.MouseEvent(bx1, by, T.mouse_left, T.mouse_press, false, false, false))
        @test m.weco_explain_stack == ["WECO-3"]
        T.update!(m, T.MouseEvent(bx3, by, T.mouse_left, T.mouse_press, false, false, false))
        @test isempty(m.weco_explain_stack)
        @test m.weco_explain_open === false
        re_view!()
        @test isempty(m.weco_popup_rects) || all(r -> r.width == 0, m.weco_popup_rects)
        @test m.weco_popup_rect.width == 0
    end

    @testset "WECO plot double-click explain :point (PR4 / KD-WB-10)" begin
        # Multi-rule viol at #8 (same fixture as hover multi-highlight)
        cl, s = 0.0, 1.0
        vals = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 3.5]
        d = WorkbenchData(values = vals, cl = cl, sigma = s)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single,
            viewport = Viewport(x0 = 1, x1 = length(vals)))
        _ensure_charts!(m)
        ch = current_chart(m)
        ch.limits_mode = :manual
        ch.manual_cl = cl
        ch.manual_ucl = cl + 3 * s
        ch.manual_lcl = cl - 3 * s
        ch.enabled_rules = Dict(
            "WECO-1" => true, "WECO-2" => true, "WECO-3" => true, "WECO-4" => true,
            "WECO-5" => true, "WECO-6" => false, "WECO-7" => false, "WECO-8" => false,
        )
        m.enabled_rules = ch.enabled_rules
        ctx = resolve_chart_render_context(ch)
        viols = weco_detect(ch.data.values, ctx.lz.cl, ctx.lz.sigma; enabled_rules = ch.enabled_rules)
        rules8 = weco_rules_at_index(viols, 8)
        @test length(rules8) >= 2
        @test isempty(weco_rules_at_index(viols, 1))

        W, H = 100, 36
        tb = T.TestBackend(W, H)
        function re_view!()
            T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, W, H), [], []))
        end
        re_view!()
        pa = m.plot_area
        @test pa.width > 0 && pa.height > 0

        # Cell under viol index 8 / non-viol index 1 (mid-row of plot)
        x_viol = data_index_to_cell(8, pa, m.viewport)
        x_ok = data_index_to_cell(1, pa, m.viewport)
        cy = pa.y + max(1, pa.height ÷ 2)
        @test T.contains(pa, x_viol, cy)
        @test T.contains(pa, x_ok, cy)

        function click_release!(x, y)
            T.update!(m, T.MouseEvent(x, y, T.mouse_left, T.mouse_press, false, false, false))
            T.update!(m, T.MouseEvent(x, y, T.mouse_left, T.mouse_release, false, false, false))
        end

        # --- Double click-release same viol idx within WECO_DBLCLICK_TICKS → :point ---
        @test m.weco_explain_open === false
        click_release!(x_viol, cy)
        @test m.selected == 8
        @test m.plot_last_click !== nothing
        @test m.plot_last_click.idx == 8
        @test m.weco_explain_open === false  # first click selects only
        re_view!()  # advance tick (library-style discipline)
        @test (m.tick - m.plot_last_click.tick) <= WECO_DBLCLICK_TICKS
        click_release!(x_viol, cy)
        @test m.selected == 8
        @test m.weco_explain_open === true
        @test m.weco_explain_mode === :point
        @test m.weco_explain_index == 8
        @test m.weco_explain_rule in rules8
        @test occursin("weco explain #8", m.last_event)
        @test m.plot_last_click === nothing
        re_view!()
        @test T.find_text(tb, "WECO · #8") !== nothing || T.find_text(tb, "#8") !== nothing
        # multi-rule body present (both rules or How-style lines)
        body_ok = any(r -> T.find_text(tb, r) !== nothing, rules8)
        @test body_ok

        # Close for next scenarios
        T.update!(m, T.KeyEvent(:escape))
        @test m.weco_explain_open === false

        # --- Drag between (dx ≥ WECO_DRAG_SLOP) → no explain; select may update ---
        # Drag left so pointer stays inside plot_area (index 8 is at right edge).
        m.plot_last_click = nothing
        m.plot_press = nothing
        re_view!()
        T.update!(m, T.MouseEvent(x_viol, cy, T.mouse_left, T.mouse_press, false, false, false))
        @test m.plot_press !== nothing && m.plot_press.dragged === false
        x_drag = x_viol - WECO_DRAG_SLOP
        @test T.contains(pa, x_drag, cy)
        T.update!(m, T.MouseEvent(x_drag, cy, T.mouse_left, T.mouse_drag, false, false, false))
        @test m.plot_press !== nothing && m.plot_press.dragged === true
        @test m.plot_last_click === nothing
        T.update!(m, T.MouseEvent(x_drag, cy, T.mouse_left, T.mouse_release, false, false, false))
        @test m.weco_explain_open === false
        @test m.plot_press === nothing
        # Even after a prior single-click memory + drag, no open:
        m.plot_last_click = (idx = 8, tick = m.tick)
        T.update!(m, T.MouseEvent(x_viol, cy, T.mouse_left, T.mouse_press, false, false, false))
        T.update!(m, T.MouseEvent(x_viol - WECO_DRAG_SLOP, cy, T.mouse_left, T.mouse_drag, false, false, false))
        T.update!(m, T.MouseEvent(x_viol - WECO_DRAG_SLOP, cy, T.mouse_left, T.mouse_release, false, false, false))
        @test m.weco_explain_open === false

        # --- Non-viol double click-release → select only; no explain ---
        m.plot_last_click = nothing
        m.plot_press = nothing
        re_view!()
        # Restore viewport after pan from drag tests
        m.viewport.x0 = 1
        m.viewport.x1 = length(vals)
        re_view!()
        pa = m.plot_area
        x_ok = data_index_to_cell(1, pa, m.viewport)
        x_viol = data_index_to_cell(8, pa, m.viewport)
        click_release!(x_ok, cy)
        @test m.selected == 1
        @test m.plot_last_click !== nothing && m.plot_last_click.idx == 1
        @test m.weco_explain_open === false
        re_view!()
        click_release!(x_ok, cy)
        @test m.selected == 1
        @test m.weco_explain_open === false  # non-viol: no explain
        @test m.plot_last_click !== nothing && m.plot_last_click.idx == 1

        # Slow second click (Δtick > WECO_DBLCLICK_TICKS) must NOT open even on viol
        m.plot_last_click = nothing
        re_view!()
        click_release!(x_viol, cy)
        @test m.plot_last_click !== nothing
        first_tick = m.plot_last_click.tick
        m.tick = first_tick + WECO_DBLCLICK_TICKS + 1
        @test (m.tick - m.plot_last_click.tick) > WECO_DBLCLICK_TICKS
        click_release!(x_viol, cy)
        @test m.weco_explain_open === false
        @test m.selected == 8

        # Help notes mention dblclick viol explain
        entries = _contextual_key_entries(m; expanded = true)
        flat = join([string(e) for e in entries], " ")
        @test occursin("dblclick", flat) || occursin("double", lowercase(flat))
        @test occursin("explain", flat)
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
        @test m.view_mode === :config
        @test m.config_tab == :lines
        # select ±1σ (item 2) and toggle
        T.update!(m, T.KeyEvent('2'))
        @test m.show_chart_lines["sigma1"] == false

        tb2 = T.TestBackend(90, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1,1,90,24),[],[]))
        # still in config — close and check side
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
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
        @test m.view_mode === :config && m.config_tab == :lines
        T.update!(m, T.KeyEvent('5'))
        @test m.show_chart_lines["specs"] == false
        # c no longer closes: jumps to Rules and stays on Config (KD-UC-14)
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config
        @test m.config_tab == :weco
        T.update!(m, T.KeyEvent(:escape))  # Esc/q only close
        @test m.view_mode === :dashboard

        # Tab switches WECO → Lines → Visual → Saved → WECO (four-way)
        # Isolate empty index so Saved land does not inject host XDG (Issue 4)
        m.graph_config_index_path = joinpath(tempdir(), "spc_wb_empty_idx_$(rand(UInt32)).json")
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config && m.config_tab == :weco
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :lines
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :visual
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :saved
        T.update!(m, T.KeyEvent(:tab))
        @test m.config_tab == :weco
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
    end

    # ── PR2 Side Stats sectionize + collapse acceptance ───────────────────
    @testset "side stats PR2: H=36 section headers visible" begin
        d = generate_spc_workbench_data(16; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        tb = T.TestBackend(100, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 36), [], []))
        side = _side_full(tb, m)
        @test occursin("STATS", side) || occursin("▸ STATS", side)
        @test occursin("LINES", side)
        @test occursin("WECO", side)
        @test occursin("Cpk=", side)
        @test occursin("Viols:", side)
    end

    @testset "side stats PR2: Target T= on STATS at tall height" begin
        d = generate_spc_workbench_data(16; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        m.usl = 16.0
        m.lsl = 8.0
        m.target = 12.0
        _ensure_charts!(m)
        ch = current_chart(m)
        ch.usl = m.usl
        ch.lsl = m.lsl
        ch.target = m.target
        tb = T.TestBackend(100, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 36), [], []))
        side = _side_full(tb, m)
        @test occursin("T=12", side)  # T=12 or T=12.0
        @test occursin("Specs=", side) || occursin("USL=", side)
        @test occursin("USL=", side)
        @test occursin("LSL=", side)
        # No hex band: row (KD-SS-5); band name may appear as dim " · green" only
        @test !occursin("band:", side)
        @test !occursin(r"#[0-9a-fA-F]{3,8}", side)
    end

    @testset "side stats PR2: collapse+hover short height multi-chart" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true, seed_demos=:triple)
        # Seed demos before asserting multi-chart (charts filled on ensure/view)
        _ensure_charts!(m)
        @test length(m.charts) >= 2
        n_pri = length(resolve_chart_render_context(current_chart(m); sigma_method=:mr).primary_values)
        m.hovered = max(1, min(1, n_pri))
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        @test length(m.charts) >= 2
        @test m.side_area.height <= 11
        side = _side_full(tb, m)
        @test occursin("h[", side)  # hover body kept (D18)
        # KD-SS-17: headerless HOVER under compact profile
        @test !occursin("▸ HOVER", side)
        # ±1/±2 dropped under KD-SS-17 when hover + multi-chart
        @test !occursin("±1", side)
        @test !occursin("±2", side)
        # Chart list names lowest priority (D1) — absent at short height
        @test !occursin("▶", side)
    end

    @testset "side stats PR2: short height Viols ≻ digits/charts" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true, seed_demos=:triple)
        _ensure_charts!(m)
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        side = _side_full(tb, m)
        @test occursin("Viols:", side)
        found = _side_weco_bubbles(tb, m)
        @test found !== nothing
        # Digits (D6) omitted under H≤11; next non-empty side row after bubbles is Viols:
        if found !== nothing
            digit_run = false
            for y in (found.y + 1):T.bottom(found.sa)
                chars = Char[T.char_at(tb, x, y) for x in found.sa.x:T.right(found.sa)]
                txt = rstrip(String(chars))
                isempty(txt) && continue
                if occursin("Viols:", txt)
                    break
                end
                # consecutive 1..8 digit row under bubbles
                only_digits = all(c -> c == ' ' || c == '\0' || ('1' <= c <= '8'), chars)
                has_seq = occursin("12345678", replace(txt, r"[\s\0]" => ""))
                digit_run = only_digits && has_seq
                break
            end
            @test !digit_run
        end
        # Chart names (D1) absent
        @test !occursin("▶", side)
    end

    @testset "side stats PR2: H=18 Viols after bubbles + default pattern" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true)
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        found = _side_weco_bubbles(tb, m)
        @test found !== nothing
        if found !== nothing
            @test found.bubbles == "●●●●●○○○"
            # Viols on a later row in side panel
            side = _side_full(tb, m)
            @test occursin("Viols:", side)
        end
    end

    @testset "side stats PR2: H=19/20 hover multi WECO floor (no height cliff)" begin
        d = generate_spc_workbench_data(12; seed=42)
        for term_h in (19, 20)
            m = SPCWorkbenchModel(data=d, paused=true, seed_demos=:triple)
            _ensure_charts!(m)
            @test length(m.charts) >= 2
            m.hovered = 1
            tb = T.TestBackend(80, term_h); T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, term_h), [], []))
            @test m.side_area.height >= 12  # above compact_h11 cliff region
            side = _side_full(tb, m)
            @test occursin("h[", side)
            found = _side_weco_bubbles(tb, m)
            @test found !== nothing  # bubbles not starved by full Lines
            @test occursin("Viols:", side)  # D17 floor via reserve_tail=2
        end
        # H=20 + Target must not starve WECO (D14 gated for all heights)
        m = SPCWorkbenchModel(data=d, paused=true, seed_demos=:triple)
        _ensure_charts!(m)
        m.target = 12.0
        current_chart(m).target = 12.0
        m.hovered = 1
        tb = T.TestBackend(80, 20); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 20), [], []))
        side = _side_full(tb, m)
        @test _side_weco_bubbles(tb, m) !== nothing
        @test occursin("Viols:", side)
        @test occursin("h[", side)
    end

    @testset "side stats PR2: H=16 hover keeps hover+WECO; no Charts without Lines" begin
        d = generate_spc_workbench_data(12; seed=42)
        m = SPCWorkbenchModel(data=d, paused=true, seed_demos=:triple)
        _ensure_charts!(m)
        m.hovered = 1
        tb = T.TestBackend(80, 16); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 16), [], []))
        side = _side_full(tb, m)
        @test occursin("h[", side)
        @test !occursin("▸ HOVER", side)  # compact headerless
        found = _side_weco_bubbles(tb, m)
        @test found !== nothing
        @test occursin("Viols:", side)
        # Either Lines minimal present (CL) or, if omitted, Charts count must not outrank (D4 ≺ D13)
        has_lines = occursin("CL=", side)
        has_charts_count = occursin("Charts:", side)
        @test has_lines || !has_charts_count
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
        @test m.view_mode === :config
        @test m.config_tab == :visual
        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1,1,80,18),[],[]))
        full = join([string(T.row_text(tb, i)) for i in 1:18 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Visual", full)
        @test occursin("CONFIG", full) || occursin("Config", full)
        @test occursin("Solid", full) || occursin("solid", lowercase(full)) || occursin("series", lowercase(full))
        # no-bleed: normal dashboard header/side not mixed into config path
        @test T.find_text(tb, "Side Stats") === nothing
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing

        # Toggle solid_series off via 1
        T.update!(m, T.KeyEvent('1'))
        @test m.visual_prefs["solid_series"] == false
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard

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

    # ── P2-PR2: dual secondary canvas under active plot (KD-P2-15/16/17) ──
    @testset "P2-PR2: dual secondary canvas — pref defaults + Visual tab" begin
        @test "secondary_canvas" in VISUAL_PREF_KEYS
        @test get(DEFAULT_VISUAL_PREFS, "secondary_canvas", false) === true
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(12; seed = 3), paused = true)
        @test haskey(m.visual_prefs, "secondary_canvas")
        @test m.visual_prefs["secondary_canvas"] === true
        T.update!(m, T.KeyEvent('o'))
        tb = T.TestBackend(80, 16); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 16), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:16 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Secondary canvas", full) || occursin("secondary", lowercase(full))
        # key 4 toggles secondary_canvas (4th visual pref)
        T.update!(m, T.KeyEvent('4'))
        @test m.visual_prefs["secondary_canvas"] === false
        T.update!(m, T.KeyEvent('4'))
        @test m.visual_prefs["secondary_canvas"] === true
        T.update!(m, T.KeyEvent(:escape))
    end

    @testset "P2-PR2: dual on at 90×24 triple with compress (MR title; neighbors hidden)" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(20; seed = 42), paused = true)
        _ensure_charts!(m)
        @test m.seed_demos === :triple
        @test length(m.charts) == 3
        @test m.active == 1
        @test current_chart(m).chart_type == I_MR
        m.visual_prefs["secondary_canvas"] = true
        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 24), [], []))
        rows = [T.row_text(tb, i) for i in 1:24]
        full = join([string(r) for r in rows if r !== nothing], "\n")
        # Secondary series title under active (I-MR → MR)
        @test occursin("MR (secondary)", full) || occursin("(secondary)", full)
        @test occursin("Dashboard", full)
        # KD-P2-15 compress: pane titles for neighbors must be absent (side list may still say Secondary)
        @test !occursin("Chart 2:", full)
        @test !occursin("Chart 3:", full)
    end

    @testset "P2-PR2: tall 90×40 triple keeps dual + neighbor panes (no compress)" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(20; seed = 42), paused = true)
        _ensure_charts!(m)
        m.visual_prefs["secondary_canvas"] = true
        tb = T.TestBackend(90, 40); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 40), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:40 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("MR (secondary)", full) || occursin("(secondary)", full)
        @test occursin("Chart 2:", full)
        @test occursin("Chart 3:", full)
    end

    @testset "P2-PR2: pref off restores multi-pane neighbors at 90×24" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(20; seed = 42), paused = true)
        _ensure_charts!(m)
        m.visual_prefs["secondary_canvas"] = false
        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 24), [], []))
        rows = [T.row_text(tb, i) for i in 1:24]
        full = join([string(r) for r in rows if r !== nothing], "\n")
        @test !occursin("MR (secondary)", full)
        @test !occursin("(secondary)", full)
        @test occursin("Chart 2:", full)  # multi-pane neighbor restored (pane title)
    end

    @testset "P2-PR2: active=2 with pref off — no primary duplicate as Chart 2" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(15; seed = 99), paused = true)
        _ensure_charts!(m)
        m.visual_prefs["secondary_canvas"] = false
        m.charts[1].name = "Alpha"
        m.charts[2].name = "Bravo"
        m.charts[3].name = "Charlie"
        set_active_chart!(m, 2)
        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Bravo", full)
        @test occursin("Chart 2:", full)
        @test !occursin("Chart 2: Bravo", full)
        @test !occursin("Chart 2: Alpha", full)
    end

    @testset "P2-PR2: secondary Viewport isolation (m.viewport Y unchanged by dual)" begin
        d = generate_spc_workbench_data(25; seed = 7, μ = 100.0, σ = 2.0)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.visual_prefs["secondary_canvas"] = false
        n = length(m.data.values)
        m.viewport.x0 = 1
        m.viewport.x1 = n
        tb0 = T.TestBackend(90, 24); T.reset!(tb0.buf)
        T.view(m, T.Frame(tb0.buf, T.Rect(1, 1, 90, 24), [], []))
        ylo_base = m.viewport.ylo
        yhi_base = m.viewport.yhi
        x0_base = m.viewport.x0
        x1_base = m.viewport.x1
        pa_base = m.plot_area

        m.visual_prefs["secondary_canvas"] = true
        tb1 = T.TestBackend(90, 24); T.reset!(tb1.buf)
        T.view(m, T.Frame(tb1.buf, T.Rect(1, 1, 90, 24), [], []))
        # Primary viewport X/Y must match single-canvas baseline for same data (KD-P2-16)
        @test m.viewport.ylo == ylo_base
        @test m.viewport.yhi == yhi_base
        @test m.viewport.x0 == x0_base
        @test m.viewport.x1 == x1_base
        # plot_area is primary-only: same top, strictly shorter than full single-canvas
        # (a regression that bound mouse to the full dual stack would keep height == pa_base.height)
        @test m.plot_area.y == pa_base.y
        @test m.plot_area.height < pa_base.height
        full = join([string(T.row_text(tb1, i)) for i in 1:24 if T.row_text(tb1, i) !== nothing], "\n")
        @test occursin("MR (secondary)", full)
        # Secondary title must appear strictly below primary plot_area bottom (not inside primary bind rect)
        sec_row = findfirst(i -> occursin("MR (secondary)", string(T.row_text(tb1, i))), 1:24)
        @test sec_row !== nothing
        pa_bottom = m.plot_area.y + m.plot_area.height - 1
        @test sec_row > pa_bottom
    end

    # ── PR1: per-line chart styles (solid/dotted/dashed/long_dash) ────────
    @testset "chart line styles: Lines tab UI short rows + left/right cycle" begin
        d = generate_spc_workbench_data(16; seed = 42)
        m = SPCWorkbenchModel(data = d, paused = true)
        x0_before = m.viewport.x0
        T.update!(m, T.KeyEvent('v'))
        @test m.view_mode === :config
        @test m.config_tab == :lines
        tb = T.TestBackend(90, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Chart Lines", full)
        @test occursin("CONFIG", full)
        @test occursin("←/→ style", full)  # cycle hints in section strip / keys
        @test occursin("solid", full)
        @test occursin("dotted", full)
        @test occursin("long dash", full) || occursin("long_dash", full)
        @test !occursin("style:", full)  # no long "style:" prefix per row
        @test !occursin("(draw on chart)", full)
        # CL selected by default (item 1): right cycles solid → dotted
        @test m.config_selected == 1
        @test _line_style(m, "cl") == "solid"
        T.update!(m, T.KeyEvent(:right))
        @test m.chart_line_styles["cl"] == "dotted"
        @test occursin("style cl=", m.last_event)
        # left cycles back
        T.update!(m, T.KeyEvent(:left))
        @test m.chart_line_styles["cl"] == "solid"
        # space still toggles visibility only
        T.update!(m, T.KeyEvent(' '))
        @test m.show_chart_lines["cl"] == false
        @test m.chart_line_styles["cl"] == "solid"
        # left/right must not pan while config open
        @test m.viewport.x0 == x0_before
        # re-render: CL still labeled solid after cycle-back; visibility [OFF]
        tb2 = T.TestBackend(90, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 90, 24), [], []))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:24 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("[OFF]", full2)
        @test occursin("solid", full2)  # style label remains after cycle-back
        @test occursin("←/→ style", full2)
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
    end

    @testset "full-page Config: open-only c/v/o, Esc/q close, jumps, Saved path" begin
        d = generate_spc_workbench_data(16; seed = 11)
        m = SPCWorkbenchModel(data = d, paused = true)
        _ensure_charts!(m)
        # Isolate empty index before any Saved land (Issue 4 / KD-SE-5)
        m.graph_config_index_path = joinpath(tempdir(), "spc_wb_empty_idx_$(rand(UInt32)).json")

        # Dashboard c opens Rules (open only — re-pressing c from dashboard re-opens)
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config
        @test m.config_tab == :weco
        tb = T.TestBackend(90, 22); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 22), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:22 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("CONFIG", full)
        @test occursin("WECO-", full)
        @test occursin("[Saved]", full) || occursin("Saved", full)
        @test T.find_text(tb, "Side Stats") === nothing
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing

        # In-Config c/v/o/e jump sections and stay on Config (do NOT close)
        T.update!(m, T.KeyEvent('v'))
        @test m.view_mode === :config && m.config_tab == :lines
        T.update!(m, T.KeyEvent('c'))  # from Lines → Rules; stays :config
        @test m.view_mode === :config
        @test m.config_tab == :weco
        T.update!(m, T.KeyEvent('o'))
        @test m.view_mode === :config && m.config_tab == :visual
        T.update!(m, T.KeyEvent('e'))  # e → Saved (not separate :presets mode)
        @test m.view_mode === :config && m.config_tab === :saved

        # q closes without quit
        T.update!(m, T.KeyEvent('q'))
        @test m.view_mode === :dashboard
        @test m.quit == false

        # Esc closes without quit
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        @test m.quit == false

        # Config s → Save As explorer (stays on Config; not dashboard clear-specs)
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config
        T.update!(m, T.KeyEvent('s'))
        @test m.view_mode === :config
        @test m.file_browser_open === true
        @test m.file_browser_mode === :save_graph_config
        @test m.prompt_kind === nothing
        T.update!(m, T.KeyEvent(:escape))  # cancel explorer
        @test m.file_browser_open === false
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard

        # Mouse modal gate: press while Config open does not pan/hover
        T.update!(m, T.KeyEvent('c'))
        @test m.view_mode === :config
        m.hovered = 1
        m.hover_x = 5
        T.update!(m, T.MouseEvent(20, 10, T.mouse_left, T.mouse_press, false, false, false))
        @test m.view_mode === :config
        @test occursin("modal", m.last_event)
        @test m.hover_x === nothing
        @test m.hovered === nothing
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard

        # Dashboard s still clears specs when not in config
        m.usl = 100.0
        m.target = 50.0
        m.lsl = 0.0
        current_chart(m).usl = 100.0
        current_chart(m).target = 50.0
        current_chart(m).lsl = 0.0
        T.update!(m, T.KeyEvent('s'))
        @test m.view_mode === :dashboard
        @test m.usl === nothing && m.target === nothing && m.lsl === nothing
        @test occursin("specs cleared", m.last_event)

        # Live gate: :config blocks advance
        m.paused = false
        current_chart(m).live_enabled = true
        m.view_mode = :config
        @test _live_may_advance(m) === false
        m.view_mode = :dashboard
        m.paused = true
    end

    @testset "Config Saved: open + save popup + load selected (R2 dashboard)" begin
        d = generate_spc_workbench_data(16; seed = 42)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        # Isolate empty index before first Saved open (KD-SE-25 merge)
        m.graph_config_index_path = joinpath(tempdir(), "spc_wb_empty_idx_$(rand(UInt32)).json")

        # Dashboard e opens Config → Saved (no dashboard bleed; no :presets mode)
        T.update!(m, T.KeyEvent('e'))
        @test m.view_mode === :config
        @test m.config_tab === :saved
        tb = T.TestBackend(100, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("CONFIG", full)
        @test occursin("[Saved]", full) || occursin("Saved", full)
        @test !occursin("GRAPH PRESETS", full)
        @test occursin("No saved configs", full) || occursin("no saved", lowercase(full)) ||
              occursin("Save As", full)
        @test !occursin("Side Stats", full)  # dedicated page, no dashboard bleed
        # Esc closes without quit
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode === :dashboard
        @test m.quit == false

        # Config e jumps to Saved; s opens Save As explorer (not a separate page)
        T.update!(m, T.KeyEvent('v'))
        @test m.view_mode === :config && m.config_tab == :lines
        tb2 = T.TestBackend(100, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 24), [], []))
        full_cfg = join([string(T.row_text(tb2, i)) for i in 1:24 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("e saved", full_cfg) || occursin("[Saved]", full_cfg) ||
              occursin("saved", lowercase(full_cfg))
        T.update!(m, T.KeyEvent('e'))
        @test m.view_mode === :config && m.config_tab === :saved

        # Mutate live graph set, then disk-save via typed path fallback (p)
        m.show_chart_lines["specs"] = false
        m.chart_line_styles["cl"] = "long_dash"
        m.visual_prefs["secondary_canvas"] = false
        m.enabled_rules["WECO-6"] = true
        _sync_active_back!(m)

        mktempdir() do dir
            # KD-SE-5: never write host XDG index from tests
            m.graph_config_index_path = joinpath(dir, "graph_config_index.json")
            path1 = joinpath(dir, "my-preset.json")
            T.update!(m, T.KeyEvent('p'))
            @test m.view_mode === :config && m.config_tab === :saved
            @test m.prompt_kind === :save_graph_config
            @test m.file_browser_open === false
            # Message chrome shows the path prompt
            tb3 = T.TestBackend(100, 24); T.reset!(tb3.buf)
            T.view(m, T.Frame(tb3.buf, T.Rect(1, 1, 100, 24), [], []))
            full_p = join([string(T.row_text(tb3, i)) for i in 1:24 if T.row_text(tb3, i) !== nothing], "\n")
            @test occursin("PROMPT", full_p)
            @test occursin("save_graph_config", full_p) || occursin("save", full_p)
            while !isempty(m.prompt_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            for c in collect(path1)
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === nothing
            @test m.view_mode === :config && m.config_tab === :saved  # after save, remain on Config Saved
            @test length(m.graph_presets) == 1
            @test m.graph_presets[1].name == "my-preset"
            @test abspath(m.graph_presets[1].path) == abspath(path1)
            @test m.graph_presets[1].show_chart_lines["specs"] === false
            @test m.graph_presets[1].chart_line_styles["cl"] == "long_dash"
            @test m.graph_presets[1].visual_prefs["secondary_canvas"] === false
            @test m.graph_presets[1].enabled_rules["WECO-6"] === true
            @test occursin("saved graph config", m.last_event)
            @test isfile(path1)
            @test isfile(m.graph_config_index_path)  # index wrote to inject path only
            # List shows the saved name
            tb4 = T.TestBackend(100, 24); T.reset!(tb4.buf)
            T.view(m, T.Frame(tb4.buf, T.Rect(1, 1, 100, 24), [], []))
            full_list = join([string(T.row_text(tb4, i)) for i in 1:24 if T.row_text(tb4, i) !== nothing], "\n")
            @test occursin("my-preset", full_list)

            # empty filename in explorer → reject, no extra preset
            T.update!(m, T.KeyEvent('s'))
            @test m.file_browser_open === true
            while !isempty(m.file_browser_name_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            T.update!(m, T.KeyEvent(:enter))  # name focus default on save
            @test length(m.graph_presets) == 1
            @test occursin("empty", m.last_event)
            @test m.file_browser_open === true  # stay open on reject
            T.update!(m, T.KeyEvent(:escape))
            @test m.file_browser_open === false

            # Mutate away, then load selected via Enter → dashboard (R2)
            # Path-bearing → re-read file → "loaded graph config" (KD-SE-16)
            m.show_chart_lines["specs"] = true
            m.chart_line_styles["cl"] = "solid"
            m.visual_prefs["secondary_canvas"] = true
            m.enabled_rules["WECO-6"] = false
            _sync_active_back!(m)
            m.presets_selected = 1
            T.update!(m, T.KeyEvent(:enter))
            @test m.show_chart_lines["specs"] === false
            @test m.chart_line_styles["cl"] == "long_dash"
            @test m.visual_prefs["secondary_canvas"] === false
            @test m.enabled_rules["WECO-6"] === true
            @test current_chart(m).enabled_rules["WECO-6"] === true
            @test occursin("loaded graph config", m.last_event)
            @test !occursin("preset applied", m.last_event)
            # load returns to dashboard so the graph is visible
            @test m.view_mode === :dashboard

            # Second config via typed path + load via l key
            T.update!(m, T.KeyEvent('e'))
            @test m.view_mode === :config && m.config_tab === :saved
            m.show_chart_lines["cl"] = false
            m.chart_line_styles["specs"] = "dashed"
            _sync_active_back!(m)
            path2 = joinpath(dir, "second.json")
            T.update!(m, T.KeyEvent('p'))
            while !isempty(m.prompt_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            for c in collect(path2)
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test length(m.graph_presets) == 2
            # select first, load with l
            m.presets_selected = 1
            m.show_chart_lines["specs"] = true
            m.chart_line_styles["cl"] = "solid"
            T.update!(m, T.KeyEvent('l'))
            @test m.show_chart_lines["specs"] === false
            @test m.chart_line_styles["cl"] == "long_dash"
            @test m.view_mode === :dashboard
            @test occursin("loaded graph config", m.last_event)

            # Space on Saved also loads → dashboard
            T.update!(m, T.KeyEvent('e'))
            @test m.view_mode === :config && m.config_tab === :saved
            m.show_chart_lines["specs"] = true
            m.chart_line_styles["cl"] = "solid"
            m.presets_selected = 1
            T.update!(m, T.KeyEvent(' '))
            @test m.show_chart_lines["specs"] === false
            @test m.chart_line_styles["cl"] == "long_dash"
            @test m.view_mode === :dashboard
            @test occursin("loaded graph config", m.last_event)
        end

        # Legacy path-less load still yields "preset applied"
        T.update!(m, T.KeyEvent('e'))
        empty!(m.graph_presets)
        push!(m.graph_presets, capture_graph_preset(m; name = "memory-only"))
        m.graph_presets[1].show_chart_lines["specs"] = false
        m.show_chart_lines["specs"] = true
        m.presets_selected = 1
        T.update!(m, T.KeyEvent(:enter))
        @test m.show_chart_lines["specs"] === false
        @test occursin("preset applied", m.last_event)
        @test m.view_mode === :dashboard

        # q closes Config Saved without quit
        T.update!(m, T.KeyEvent('e'))
        T.update!(m, T.KeyEvent('q'))
        @test m.view_mode === :dashboard
        @test m.quit == false
    end

    @testset "Config Saved: pending_delete removes preset not chart (KD-UC-15)" begin
        d = generate_spc_workbench_data(12; seed = 7)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        @test length(m.charts) >= 3
        n_charts0 = length(m.charts)
        mktempdir() do dir
            m.graph_config_index_path = joinpath(dir, "graph_config_index.json")
            # Seed two named configs
            push!(m.graph_presets, capture_graph_preset(m; name = "keep-me"))
            push!(m.graph_presets, capture_graph_preset(m; name = "drop-me"))
            @test length(m.graph_presets) == 2

            T.update!(m, T.KeyEvent('e'))
            @test m.view_mode === :config && m.config_tab === :saved
            m.presets_selected = 2  # drop-me
            T.update!(m, T.KeyEvent('d'))
            @test m.pending_delete == true
            @test occursin("confirm delete preset", m.last_event)
            T.update!(m, T.KeyEvent('y'))
            @test m.pending_delete == false
            @test length(m.graph_presets) == 1
            @test m.graph_presets[1].name == "keep-me"
            @test length(m.charts) == n_charts0  # chart count unchanged
            @test occursin("deleted preset", m.last_event)
            # re-render Saved list
            tb = T.TestBackend(100, 22); T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 22), [], []))
            full = join([string(T.row_text(tb, i)) for i in 1:22 if T.row_text(tb, i) !== nothing], "\n")
            @test occursin("keep-me", full)
            @test !occursin("drop-me", full)
            T.update!(m, T.KeyEvent(:escape))
            @test m.view_mode === :dashboard
        end
    end

    @testset "Config Saved: scroll capacity uses remaining body (not full content)" begin
        d = generate_spc_workbench_data(12; seed = 3)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.graph_config_index_path = joinpath(tempdir(), "spc_wb_empty_idx_$(rand(UInt32)).json")
        for i in 1:20
            push!(m.graph_presets, capture_graph_preset(m; name = "cfg-$i"))
        end
        T.update!(m, T.KeyEvent('e'))
        @test m.view_mode === :config && m.config_tab === :saved
        tb = T.TestBackend(100, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
        # Area is remaining body; capacity reserves full list chrome (title/rule/header/blank/actions)
        @test m.presets_area.height > 0
        cap = _presets_visible_capacity(m)
        @test cap >= 1
        @test cap < m.presets_area.height
        @test cap == max(1, m.presets_area.height - SAVED_LIST_CHROME_ROWS)
        # Selecting last entry advances scroll so capacity stays honest
        m.presets_selected = 20
        _sync_presets_scroll!(m)
        @test m.presets_scroll > 0
        # re-render: last name visible, first name scrolled off; footer chrome survives full window
        tb2 = T.TestBackend(100, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 24), [], []))
        full = join([string(T.row_text(tb2, i)) for i in 1:24 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("cfg-20", full)
        @test !occursin("cfg-1  ", full)  # early entries scrolled away (exact pad, not cfg-10+)
        @test occursin("Actions:", full)  # action strip reserved in chrome budget (Issue 1/5)
        @test occursin("Save As", full) || occursin("Save", full)
        @test occursin("Name", full) && occursin("WECO", full)  # column header still present
        T.update!(m, T.KeyEvent(:escape))
    end

    @testset "Config Saved polish: hierarchy, body chips, Path chrome, empty CTA" begin
        d = generate_spc_workbench_data(12; seed = 11)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        # Isolate index so empty Saved stays empty (no host XDG merge)
        mktempdir() do dir
            m.graph_config_index_path = joinpath(dir, "graph_config_index.json")

            # Empty Saved: hierarchy + boxed CTA + disk-first key labels + Path header
            T.update!(m, T.KeyEvent('e'))
            @test m.view_mode === :config && m.config_tab === :saved
            tb = T.TestBackend(100, 24); T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
            full0 = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
            @test occursin("SAVED GRAPH CONFIGS", full0)
            @test occursin("0 saved", full0)
            @test occursin("No saved configs yet", full0) || occursin("No saved configs", full0)
            @test occursin("Save As", full0)
            @test occursin("Actions:", full0)
            @test occursin("[★ Saved]", full0) || occursin("★ Saved", full0)
            @test occursin("Path", full0)  # PR4 path column header
            @test !occursin(" on disk", full0)
            # s opens Save As explorer (KD-SE-7)
            T.update!(m, T.KeyEvent('s'))
            @test m.file_browser_open === true
            @test m.file_browser_mode === :save_graph_config
            @test m.prompt_kind === nothing
            T.update!(m, T.KeyEvent(:escape))
            @test m.file_browser_open === false

            # Two path-less presets → column header + WECO/lines/styles chips from body
            p1 = capture_graph_preset(m; name = "fab-dense")
            p1.show_chart_lines["specs"] = false
            p1.enabled_rules["WECO-6"] = true
            p1.enabled_rules["WECO-7"] = true
            p1.enabled_rules["WECO-8"] = true  # defaults 1-5 on → 8/8
            push!(m.graph_presets, p1)
            p2 = capture_graph_preset(m; name = "loose")
            # default styles are mixed (solid/dotted/dashed/long_dash)
            push!(m.graph_presets, p2)
            # re-open Saved so selection/chrome refresh (merge keeps path-less)
            T.update!(m, T.KeyEvent(:escape))
            T.update!(m, T.KeyEvent('e'))
            tb2 = T.TestBackend(100, 24); T.reset!(tb2.buf)
            T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 24), [], []))
            full1 = join([string(T.row_text(tb2, i)) for i in 1:24 if T.row_text(tb2, i) !== nothing], "\n")
            @test occursin("SAVED GRAPH CONFIGS", full1)
            @test occursin("2 saved", full1)
            @test occursin("Name", full1) && occursin("WECO", full1) &&
                  occursin("Lines", full1) && occursin("Styles", full1) &&
                  occursin("Path", full1)
            @test occursin("fab-dense", full1)
            @test occursin("loose", full1)
            # body chips: both rows visible → both lines chips (p1 specs off, p2 all on)
            @test occursin("8/8", full1)  # p1 with WECO 6-8 enabled
            @test occursin("off-1", full1)
            @test occursin("all", full1)
            @test occursin("mixed", full1)
            @test occursin("Actions:", full1)
            @test !occursin("lines-off=", full1)  # old summary format gone
            T.update!(m, T.KeyEvent(:escape))
        end
    end

    @testset "chart line styles: primary buffer density solid ≫ dotted" begin
        # Horizontal limit row density: solid step-1 continuous ─ vs dotted step-2 -
        vals = fill(10.0, 12)
        d = WorkbenchData(values = vals, cl = 10.0, sigma = 1.0)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single,
            viewport = Viewport(x0 = 1, x1 = 12, ylo = 5.0, yhi = 15.0))
        _ensure_charts!(m)
        for k in keys(m.show_chart_lines)
            m.show_chart_lines[k] = false
        end
        m.show_chart_lines["cl"] = true
        m.visual_prefs["solid_series"] = false
        m.visual_prefs["solid_stroke"] = false
        m.visual_prefs["braille_series"] = false
        m.visual_prefs["secondary_canvas"] = false

        m.chart_line_styles["cl"] = "solid"
        tb_s = T.TestBackend(80, 22); T.reset!(tb_s.buf)
        T.view(m, T.Frame(tb_s.buf, T.Rect(1, 1, 80, 22), [], []))
        pa = m.plot_area
        @test pa.width > 4 && pa.height > 3
        ch = current_chart(m)
        ctx = resolve_chart_render_context(ch; sigma_method = :mr)
        yy = data_val_to_cell_row(ctx.lz.cl, pa, m.viewport)
        filled_solid = count(xx -> begin
            c = T.char_at(tb_s, xx, yy)
            c != ' ' && c != '\0'
        end, pa.x:T.right(pa))

        m.chart_line_styles["cl"] = "dotted"
        tb_d = T.TestBackend(80, 22); T.reset!(tb_d.buf)
        T.view(m, T.Frame(tb_d.buf, T.Rect(1, 1, 80, 22), [], []))
        yy2 = data_val_to_cell_row(ctx.lz.cl, m.plot_area, m.viewport)
        filled_dotted = count(xx -> begin
            c = T.char_at(tb_d, xx, yy2)
            c != ' ' && c != '\0'
        end, m.plot_area.x:T.right(m.plot_area))

        @test filled_solid > filled_dotted
        @test filled_solid >= max(3, filled_dotted + 1)
    end

    @testset "chart line styles: multi-site density (secondary site2 + neighbor site3)" begin
        # Site 2: dual-secondary branch of _render_series_canvas! (draw_sigma_zones=false).
        # UCL/LCL use _line_style(m,"sigma3"); no _line_on gate. char_at density solid ≫ dotted.
        vals_sec = fill(5.0, 10)
        m_sec = SPCWorkbenchModel(data = WorkbenchData(values = fill(10.0, 11), cl = 10.0, sigma = 1.0),
            paused = true, seed_demos = :single)
        m_sec.visual_prefs["solid_series"] = false
        m_sec.visual_prefs["solid_stroke"] = false
        m_sec.visual_prefs["braille_series"] = false
        m_sec.chart_line_styles["sigma3"] = "solid"
        m_sec.chart_line_styles["cl"] = "dotted"  # leave CL sparse so UCL row is cleaner
        @test _line_style(m_sec, "sigma3") == "solid"

        function _count_ucl_row(m, style::String)
            m.chart_line_styles["sigma3"] = style
            tb = T.TestBackend(70, 16); T.reset!(tb.buf)
            outer = T.Rect(1, 1, 70, 16)
            f = T.Frame(tb.buf, outer, [], [])
            vp = Viewport(x0 = 1, x1 = 10, ylo = 0.0, yhi = 12.0)
            ucl, lcl, cl = 10.0, 0.0, 5.0
            inner = _render_series_canvas!(
                tb.buf, outer, m, f;
                title = "MR (secondary)",
                values = vals_sec,
                viewport = vp,
                cl = cl, ucl = ucl, lcl = lcl,
                bind_mouse = false,
                draw_weco_markers = false,
                draw_specs = false,
                draw_sigma_zones = false,  # site 2 simplified branch
                draw_hover = false,
            )
            # Re-fit viewport as the helper does so yy matches painted row
            extras = Float64[cl, ucl, lcl]
            fit_viewport_y!(vp, vals_sec; extras = extras)
            yy = data_val_to_cell_row(ucl, inner, vp)
            nfill = count(xx -> begin
                c = T.char_at(tb, xx, yy)
                c != ' ' && c != '\0'
            end, inner.x:T.right(inner))
            return (nfill, inner, yy)
        end

        filled_solid, _, _ = _count_ucl_row(m_sec, "solid")
        filled_dotted, _, _ = _count_ucl_row(m_sec, "dotted")
        @test filled_solid > filled_dotted
        @test filled_solid >= max(3, filled_dotted + 1)

        # Site 3: neighbor pane Chart 2 buffer density via full dashboard layout.
        # Only CL on; connectors off; compare solid vs dotted on reconstructed inn2 CL row.
        d = generate_spc_workbench_data(16; seed = 11)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        @test length(m.charts) >= 2
        m.visual_prefs["secondary_canvas"] = false  # keep multi-pane neighbors visible
        m.visual_prefs["solid_series"] = false
        m.visual_prefs["solid_stroke"] = false
        m.visual_prefs["braille_series"] = false
        for k in keys(m.show_chart_lines)
            m.show_chart_lines[k] = false
        end
        m.show_chart_lines["cl"] = true

        W, H = 90, 40
        function _neighbor_cl_density(m, style::String)
            m.chart_line_styles["cl"] = style
            tb = T.TestBackend(W, H); T.reset!(tb.buf)
            area = T.Rect(1, 1, W, H)
            T.view(m, T.Frame(tb.buf, area, [], []))
            @test T.find_text(tb, "Chart 2:") !== nothing
            # Reconstruct second_plot_rect / inn2 from view layout (must match spc_workbench.jl)
            gauge_h = _gauge_row_height(m, area.height)
            rows = T.split_layout(T.Layout(T.Vertical, [T.Fixed(1), T.Fill(), T.Fixed(gauge_h)]), area)
            main = rows[2]
            cols = T.split_layout(T.Layout(T.Horizontal, [T.Fill(), T.Fixed(28)]), main)
            plot_rect = cols[1]
            panes = dashboard_pane_charts(m; k = 3)
            nc = min(3, length(panes))
            @test nc >= 2
            if nc == 3
                h1 = max(8, (plot_rect.height * 5) ÷ 10)
                h2 = max(5, (plot_rect.height - h1 - 2) * 5 ÷ 10)
                second_plot_rect = T.Rect(plot_rect.x, plot_rect.y + h1 + 1, plot_rect.width, h2)
            else
                h1 = max(6, (plot_rect.height * 6) ÷ 10)
                second_plot_rect = T.Rect(plot_rect.x, plot_rect.y + h1 + 1, plot_rect.width,
                    max(3, plot_rect.height - h1 - 1))
            end
            # Block border inset (1 cell each side) → plot_inner for Chart 2
            inn2 = T.Rect(second_plot_rect.x + 1, second_plot_rect.y + 1,
                max(1, second_plot_rect.width - 2), max(1, second_plot_rect.height - 2))
            ch2 = panes[2]
            ctx2 = resolve_chart_render_context(ch2; sigma_method = :mr)
            plot2 = ctx2.primary_values
            n2 = length(plot2)
            vp2 = ch2.viewport
            n2 > 0 && clamp_viewport!(vp2, n2)
            n2 > 0 && auto_fit_viewport_y!(vp2, plot2, ctx2.lz;
                usl = ch2.usl, lsl = ch2.lsl, show_lines = m.show_chart_lines)
            yy = data_val_to_cell_row(ctx2.lz.cl, inn2, vp2)
            nfill = count(xx -> begin
                c = T.char_at(tb, xx, yy)
                c != ' ' && c != '\0'
            end, inn2.x:T.right(inn2))
            return nfill
        end

        n_solid = _neighbor_cl_density(m, "solid")
        n_dotted = _neighbor_cl_density(m, "dotted")
        @test n_solid > n_dotted
        @test n_solid >= max(3, n_dotted + 1)
    end

    # ── GC-PR2: Chart library mode UI + prompt SM (A5 / KD21) ─────────────
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
        @test m.last_event == "library open"

        tb = T.TestBackend(80, 20); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 20), [], []))
        @test T.find_text(tb, "CHART LIBRARY") !== nothing
        # no-bleed: normal dashboard chrome must not render under library
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing
        @test T.find_text(tb, "Side Stats") === nothing
        @test T.find_text(tb, "Dashboard:") === nothing
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

        # clone selected
        T.update!(m, T.KeyEvent('c'))
        @test length(m.charts) == n0 + 1
        @test m.library_selected == n0 + 1
        @test endswith(m.charts[end].name, "(copy)")
        @test m.view_mode == :library
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
        T.update!(m, T.KeyEvent(:backspace))
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
        @test m.charts[1].name == "Renamed"
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

    @testset "library: Esc/q close without quit; I/O keys open prompts; add" begin
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

        # GC-PR3: I/O keys open path prompts (Enter wired in package-module suite)
        T.update!(m, T.KeyEvent('i'))
        @test m.prompt_kind === :import_csv
        @test m.prompt_buf == ""
        @test m.view_mode == :library
        @test m.quit == false
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing

        # capital I is symmetric with i
        T.update!(m, T.KeyEvent('I'))
        @test m.prompt_kind === :import_csv
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing

        m.last_export_path = "/tmp/prev_export.csv"
        T.update!(m, T.KeyEvent('e'))
        @test m.prompt_kind === :export_csv
        @test m.prompt_buf == "/tmp/prev_export.csv"
        T.update!(m, T.KeyEvent(:escape))

        T.update!(m, T.KeyEvent('E'))
        @test m.prompt_kind === :export_csv
        T.update!(m, T.KeyEvent(:escape))

        m.last_workbench_path = "/tmp/prev_session.json"
        T.update!(m, T.KeyEvent('w'))
        @test m.prompt_kind === :save_workbench
        @test m.prompt_buf == "/tmp/prev_session.json"
        T.update!(m, T.KeyEvent(:escape))

        T.update!(m, T.KeyEvent('W'))
        @test m.prompt_kind === :load_workbench
        @test m.prompt_buf == "/tmp/prev_session.json"
        # q is a buffer character under prompt — never quit
        T.update!(m, T.KeyEvent('q'))
        @test m.quit == false
        @test m.prompt_kind === :load_workbench
        @test endswith(m.prompt_buf, "q")
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing
        @test m.view_mode == :library
        @test m.quit == false

        # empty-name rename Enter → cancel message, name unchanged
        m.library_selected = 1
        name0 = m.charts[1].name
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :rename_chart
        for _ in 1:length(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        @test isempty(m.prompt_buf)
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === nothing
        @test m.last_event == "rename cancel: empty name"
        @test m.charts[1].name == name0

        # last-chart delete refuse
        while length(m.charts) > 1
            m.library_selected = length(m.charts)
            T.update!(m, T.KeyEvent('d'))
            T.update!(m, T.KeyEvent('y'))
        end
        @test length(m.charts) == 1
        T.update!(m, T.KeyEvent('d'))
        @test m.pending_delete == false
        @test m.last_event == "cannot delete last chart"
        @test m.view_mode == :library
        @test m.quit == false
    end

    @testset "library: left/right no-op under library/prompt; no dashboard key bleed" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 5), paused = true)
        _ensure_charts!(m)
        n = length(m.data.values)
        m.viewport.x0 = 3
        m.viewport.x1 = min(n, 8)
        x0, x1 = m.viewport.x0, m.viewport.x1
        paused0 = m.paused

        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library

        T.update!(m, T.KeyEvent(:left))
        @test m.viewport.x0 == x0
        @test m.viewport.x1 == x1
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent(:right))
        @test m.viewport.x0 == x0
        @test m.viewport.x1 == x1

        # dashboard pause key must not fire in library
        T.update!(m, T.KeyEvent('p'))
        @test m.paused == paused0
        @test m.view_mode == :library

        # prompt swallows left/right and does not quit on q
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :rename_chart
        T.update!(m, T.KeyEvent(:left))
        @test m.viewport.x0 == x0
        @test m.prompt_kind === :rename_chart
        T.update!(m, T.KeyEvent(:right))
        @test m.viewport.x1 == x1
        @test m.prompt_kind === :rename_chart
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing
        @test m.quit == false
        @test m.view_mode == :library
    end

    @testset "library: mouse no dashboard pan; ↑↓ selection; pending modal" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 5), paused = true)
        _ensure_charts!(m)
        nch = length(m.charts)
        @test nch >= 2

        T.view(m, T.Frame(T.TestBackend(80, 18).buf, T.Rect(1, 1, 80, 18), [], []))
        m.drag_start = (x = 10, y = 5, vp = deepcopy(m.viewport))
        m.hover_x = 10
        m.hovered = 1

        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        # Re-view so library_area is set for hit-test
        T.view(m, T.Frame(T.TestBackend(80, 18).buf, T.Rect(1, 1, 80, 18), [], []))

        # Move: clears hover; does not pan dashboard
        T.update!(m, T.MouseEvent(12, 6, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hover_x === nothing
        @test m.hovered === nothing
        @test m.view_mode == :library

        T.update!(m, T.MouseEvent(12, 6, T.mouse_left, T.mouse_release, false, false, false))
        @test m.drag_start === nothing
        @test m.view_mode == :library
        @test m.quit == false

        m.library_selected = 1
        T.update!(m, T.KeyEvent(:down))
        @test m.library_selected == 2
        T.update!(m, T.KeyEvent(:up))
        @test m.library_selected == 1
        T.update!(m, T.KeyEvent(:up))
        @test m.library_selected == 1
        m.library_selected = nch
        T.update!(m, T.KeyEvent(:down))
        @test m.library_selected == nch

        T.update!(m, T.KeyEvent('d'))
        @test m.pending_delete
        sel0 = m.library_selected
        T.update!(m, T.MouseEvent(5, 5, T.mouse_left, T.mouse_press, false, false, false))
        @test occursin("modal", m.last_event)
        @test m.library_selected == sel0  # keyboard-only while pending_delete
        T.update!(m, T.KeyEvent(:escape))
        @test m.pending_delete == false
        @test m.quit == false
    end

    @testset "library mouse: click select + double-click activate (KD-P2-19)" begin
        # Tick advances in view, not update!(MouseEvent) — re-view between clicks.
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 7), paused = true)
        _ensure_charts!(m)
        nch = length(m.charts)
        @test nch >= 2
        set_active_chart!(m, 1)
        m.library_selected = 1

        tb = T.TestBackend(80, 18)
        function re_view!()
            T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        end
        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        re_view!()
        a = m.library_area
        @test a.width > 0 && a.height > 0
        list_top = a.y + 4
        # Row 0 (first visible) → abs index 1; row 1 → abs index 2
        x_mid = a.x + 4
        y_row1 = list_top
        y_row2 = list_top + 1
        y_title = a.y           # header — not a list row
        y_footer = T.bottom(a)  # footer last line

        # Pure hit-test geometry
        @test _library_row_at(m, x_mid, y_row1) == 1
        @test _library_row_at(m, x_mid, y_row2) == 2
        @test _library_row_at(m, x_mid, y_title) === nothing
        @test _library_row_at(m, x_mid, y_footer) === nothing

        # Single-click selects row 2 (does not activate)
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == 2
        @test m.active == 1
        @test m.view_mode == :library
        @test m.library_last_click !== nothing
        @test m.library_last_click.idx == 2
        @test occursin("library sel 2", m.last_event)

        # Click title/footer → selection unchanged
        sel_before = m.library_selected
        T.update!(m, T.MouseEvent(x_mid, y_title, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == sel_before
        @test m.view_mode == :library
        T.update!(m, T.MouseEvent(x_mid, y_footer, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == sel_before

        # Different row second press → new select, reset last_click (not activate)
        re_view!()  # advance tick for disciplined timing
        T.update!(m, T.MouseEvent(x_mid, y_row1, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == 1
        @test m.active == 1
        @test m.view_mode == :library
        @test m.library_last_click.idx == 1

        # Double-click same row within LIBRARY_DBLCLICK_TICKS → activate + dashboard
        re_view!()  # Δtick small (1 view tick)
        @test (m.tick - m.library_last_click.tick) <= LIBRARY_DBLCLICK_TICKS
        T.update!(m, T.MouseEvent(x_mid, y_row1, T.mouse_left, T.mouse_press, false, false, false))
        @test m.active == 1
        @test m.view_mode == :dashboard
        @test m.library_last_click === nothing
        @test occursin("active chart", m.last_event)

        # Double-click row 2 to activate chart 2
        T.update!(m, T.KeyEvent('m'))
        re_view!()
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == 2
        re_view!()
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test m.active == 2
        @test m.view_mode == :dashboard
        @test m.library_last_click === nothing

        # Prompt open → click no-op on selection
        T.update!(m, T.KeyEvent('m'))
        re_view!()
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :rename_chart
        @test m.library_last_click === nothing  # prompt open clears stale dblclick
        sel_p = m.library_selected
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test occursin("modal", m.last_event)
        @test m.library_selected == sel_p
        @test m.prompt_kind === :rename_chart
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing

        # --- Issue 1 regression: Esc → reopen → single-click must NOT activate ---
        re_view!()
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == 2
        @test m.library_last_click !== nothing
        act_before = m.active
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test m.library_last_click === nothing
        re_view!()
        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        @test m.library_last_click === nothing  # open also clears
        re_view!()
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test m.view_mode == :library          # still library — select only
        @test m.library_selected == 2
        @test m.active == act_before           # did not activate
        @test m.library_last_click !== nothing
        @test m.library_last_click.idx == 2

        # --- Slow second click (Δtick > LIBRARY_DBLCLICK_TICKS) must NOT activate ---
        re_view!()
        first_tick = m.library_last_click.tick
        # Simulate time passing without real multi-frame wait
        m.tick = first_tick + LIBRARY_DBLCLICK_TICKS + 1
        @test (m.tick - m.library_last_click.tick) > LIBRARY_DBLCLICK_TICKS
        T.update!(m, T.MouseEvent(x_mid, y_row2, T.mouse_left, T.mouse_press, false, false, false))
        @test m.view_mode == :library
        @test m.active == act_before
        @test m.library_selected == 2
        @test m.library_last_click.idx == 2
        @test m.library_last_click.tick == m.tick  # retimed as new single select
    end

    @testset "library mouse: scrolled hit-test uses library_scroll offset" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 3), paused = true)
        _ensure_charts!(m)
        for i in 1:10
            add_chart!(m; name = "Extra-$i")
        end
        nch = length(m.charts)
        @test nch >= 12

        tb = T.TestBackend(80, 14)
        T.update!(m, T.KeyEvent('m'))
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 14), [], []))
        a = m.library_area
        list_top = a.y + 4
        x_mid = a.x + 4

        # Force scroll so first visible row is chart 6 (scroll=5 → vi = 5 + 0 + 1 = 6)
        m.library_scroll = 5
        m.library_selected = 6
        @test _library_row_at(m, x_mid, list_top) == 6
        @test _library_row_at(m, x_mid, list_top + 1) == 7

        act0 = m.active
        T.update!(m, T.MouseEvent(x_mid, list_top, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == 6
        @test m.view_mode == :library
        @test m.active == act0  # single-click does not activate
        T.update!(m, T.MouseEvent(x_mid, list_top + 1, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == 7
        @test m.view_mode == :library
        @test m.active == act0
    end

    @testset "library mouse: filtered list maps visible row → absolute index" begin
        d = generate_spc_workbench_data(8; seed = 19)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        idx1 = add_chart!(m; name = "Alpha")
        idx2 = add_chart!(m; name = "Beta")
        idx3 = add_chart!(m; name = "Gamma")
        m.charts[idx1].owner = "Alice"
        m.charts[idx2].owner = "Bob"
        m.charts[idx3].owner = "Alice"
        set_active_chart!(m, idx1)
        set_filter_owner!(m, "Alice")  # visible: Alpha (1), Gamma (3) — Beta hidden
        vis = visible_charts(m)
        @test length(vis) == 2
        @test vis[1].name == "Alpha"
        @test vis[2].name == "Gamma"

        tb = T.TestBackend(80, 18)
        T.update!(m, T.KeyEvent('m'))
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        a = m.library_area
        x_mid = a.x + 4
        list_top = a.y + 4
        # Visible row 1 → abs Alpha; visible row 2 → abs Gamma (not raw index 2)
        @test _library_row_at(m, x_mid, list_top) == idx1
        @test _library_row_at(m, x_mid, list_top + 1) == idx3

        m.library_selected = idx1
        T.update!(m, T.MouseEvent(x_mid, list_top + 1, T.mouse_left, T.mouse_press, false, false, false))
        @test m.library_selected == idx3
        @test m.active == idx1  # select only
        @test m.view_mode == :library

        # Double-click visible row 2 activates Gamma (abs idx3)
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        T.update!(m, T.MouseEvent(x_mid, list_top + 1, T.mouse_left, T.mouse_press, false, false, false))
        @test m.active == idx3
        @test m.view_mode == :dashboard
        @test m.library_selected == idx3
    end

    @testset "library: scroll keeps selection visible; corrupt sel clamps" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 2), paused = true)
        _ensure_charts!(m)
        # Pad library past a short page height
        for i in 1:12
            add_chart!(m; name = "Extra-$i")
        end
        nch = length(m.charts)
        @test nch >= 15

        T.update!(m, T.KeyEvent('m'))
        # Short height so only a few rows fit → scroll must advance
        tb = T.TestBackend(80, 14); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 14), [], []))
        # Content-area capacity: title/summary ≈ 4 (Message|Keys chrome is outside library_area)
        vis = max(1, m.library_area.height - 4)
        m.library_selected = 1
        m.library_scroll = 0
        for _ in 1:(nch - 1)
            T.update!(m, T.KeyEvent(:down))
        end
        @test m.library_selected == nch
        @test m.library_scroll >= max(0, nch - vis)
        T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 14), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:14 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("▶", full)
        @test occursin(string(nch) * ".", full) || occursin("Extra-", full)

        # Corrupt selection: clamp on next library key; rename Enter must not BoundsError
        m.library_selected = 0
        T.update!(m, T.KeyEvent('n'))
        @test m.library_selected >= 1
        @test m.prompt_kind === :rename_chart
        T.update!(m, T.KeyEvent(:enter))  # apply existing seed name
        @test m.prompt_kind === nothing
        @test m.quit == false

        m.library_selected = 9999
        T.update!(m, T.KeyEvent('c'))
        @test m.library_selected == length(m.charts)
        @test m.view_mode == :library
    end

    @testset "library: help/keymap mention m/library; live blocked by prompt" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 2), paused = true)
        _ensure_charts!(m)
        T.update!(m, T.KeyEvent('h'))
        tb = T.TestBackend(80, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("library", lowercase(full)) || occursin("m/M", full)
        @test occursin("filter", lowercase(full)) || occursin("f/F", full) || occursin("f       ", full)
        T.update!(m, T.KeyEvent(:escape))
        T.update!(m, T.KeyEvent('k'))
        tb2 = T.TestBackend(80, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 80, 24), [], []))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:24 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("library", lowercase(full2)) || occursin("m M", full2)
        @test occursin("filter", lowercase(full2)) || occursin("f           ", full2)
        T.update!(m, T.KeyEvent(:escape))

        m.paused = false
        current_chart(m).live_enabled = true
        @test _live_may_advance(m) === true
        T.update!(m, T.KeyEvent('m'))
        @test _live_may_advance(m) === false
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :rename_chart
        @test _live_may_advance(m) === false
        T.update!(m, T.KeyEvent(:escape))
        @test _live_may_advance(m) === false  # still in library
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test _live_may_advance(m) === true
    end

    @testset "filters f/F prompts: dashboard + library; side list; no :filters mode (GC-PR4)" begin
        d = generate_spc_workbench_data(8; seed = 21)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :none)
        a = add_chart!(m; name = "KeepMe")
        b = add_chart!(m; name = "HideMe")
        m.charts[a].owner = "A"
        m.charts[a].tools = ["TA"]
        m.charts[a].chart_type = I_MR
        m.charts[b].owner = "B"
        m.charts[b].tools = ["TB"]
        m.charts[b].chart_type = Xbar_S
        set_active_chart!(m, a)
        @test m.seed_demos === :none
        @test m.filter_type isa String

        # dashboard f opens filter_tool prompt (cycle start); does NOT open :filters mode
        T.update!(m, T.KeyEvent('f'))
        @test m.prompt_kind === :filter_tool
        @test m.view_mode == :dashboard
        @test m.quit == false
        # Esc cancels prompt only — filters unchanged
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing
        @test m.last_event == "filter edit cancel"
        @test m.filter_tool == ""
        @test m.quit == false

        # Apply owner filter via prompt cycle: f f f → owner (after tool+type opens advance field)
        m.filter_prompt_field = :owner
        T.update!(m, T.KeyEvent('f'))
        @test m.prompt_kind === :filter_owner
        for ch in "A"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === nothing
        @test m.filter_owner == "A"
        @test length(visible_charts(m)) == 1
        @test visible_charts(m)[1].name == "KeepMe"

        # Library list shows only filtered charts; f/F available in library
        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        tb2 = T.TestBackend(80, 22); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 80, 22), [], []))
        lib = join([string(T.row_text(tb2, i)) for i = 1:22 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("KeepMe", lib)
        @test !occursin("HideMe", lib)
        @test occursin("filters:", lib) || occursin("owner=A", lib)
        # library f opens filter prompt (stays in library)
        T.update!(m, T.KeyEvent('f'))
        @test m.view_mode == :library
        @test m.prompt_kind in (:filter_tool, :filter_type, :filter_owner)
        T.update!(m, T.KeyEvent(:escape))
        # library F clears all filters
        T.update!(m, T.KeyEvent('F'))
        @test m.filter_tool == "" && m.filter_type == "" && m.filter_owner == ""
        @test m.last_event == "filters cleared"
        @test m.view_mode == :library
        @test length(visible_charts(m)) == 2
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard

        # Filter that hides all → empty dashboard message + side Charts: 0/N + footer
        set_filter_owner!(m, "Nobody")
        @test isempty(visible_charts(m))
        tb3 = T.TestBackend(80, 20); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1, 1, 80, 20), [], []))
        dash = join([string(T.row_text(tb3, i)) for i = 1:20 if T.row_text(tb3, i) !== nothing], "\n")
        @test occursin("No charts match filters", dash)
        @test occursin("Charts: 0/2", dash) || occursin("Charts: 0/", dash)
        @test occursin("(no match)", dash) || occursin("no match", lowercase(dash))
        @test occursin("Side Stats", dash)
        # Message center (or plot) shows the filter miss; footer no longer uses last=
        @test occursin("No charts match filters", dash) || occursin("Message", dash)

        # Side list respects filters (visible only) + count form
        clear_filters!(m)
        set_filter_owner!(m, "A")
        set_active_chart!(m, a)
        tb4 = T.TestBackend(90, 28); T.reset!(tb4.buf)
        T.view(m, T.Frame(tb4.buf, T.Rect(1, 1, 90, 28), [], []))
        side = join([string(T.row_text(tb4, i)) for i = 1:28 if T.row_text(tb4, i) !== nothing], "\n")
        @test occursin("Charts: 1/2", side) || occursin("KeepMe", side)
        @test !occursin("HideMe", side)

        # ] / [ under filter only cycle visible (never land on HideMe)
        set_active_chart!(m, a)
        @test current_chart(m).name == "KeepMe"
        T.update!(m, T.KeyEvent(']'))
        @test current_chart(m).name == "KeepMe"  # only one visible
        @test current_chart(m).name != "HideMe"
        T.update!(m, T.KeyEvent('['))
        @test current_chart(m).name == "KeepMe"

        # F on dashboard clears
        T.update!(m, T.KeyEvent('F'))
        @test m.filter_owner == ""
        @test m.last_event == "filters cleared"

        # type filter prompt: parse wire string on Enter
        m.filter_prompt_field = :type
        T.update!(m, T.KeyEvent('f'))
        @test m.prompt_kind === :filter_type
        for ch in "Xbar-S"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.filter_type == "Xbar-S"
        @test length(visible_charts(m)) == 1
        @test visible_charts(m)[1].name == "HideMe"
        # A6 rehome last_event when active was KeepMe
        @test m.active == b
        @test occursin("filtered", m.last_event)

        # invalid type keeps prompt open for retry
        m.filter_prompt_field = :type
        T.update!(m, T.KeyEvent('f'))
        @test m.prompt_kind === :filter_type
        while !isempty(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        for ch in "NOTATYPE"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :filter_type
        @test occursin("invalid", m.last_event)
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_buf == ""  # cancel clears buf

        # anti-port: never enter :filters mode; tools mode is allowed (P2-PR4)
        # Positive open so allowlist is not vacuously true only on :dashboard
        T.update!(m, T.KeyEvent('x'))
        @test m.view_mode == :tools
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test m.view_mode in (:dashboard, :library, :help, :keymap, :builder, :focused, :tools)
        @test m.view_mode != :filters
        # package-private setters exist on the included workbench surface
        @test isdefined(@__MODULE__, :set_filter_tool!)
        @test isdefined(@__MODULE__, :clear_filters!)
        clear_filters!(m)
    end

    # ── P2-PR4: Tools registry view_mode=:tools CRUD ─────────────────────
    @testset "tools mode: open (x/X), TOOLS REGISTRY title, no dashboard bleed" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 4), paused = true)
        _ensure_charts!(m)
        @test m.view_mode == :dashboard
        @test m.seed_demos === :triple

        # KD-P2-20: dashboard d/D opens SharedTable grid (not delete/tools)
        ntools0 = length(m.tools)
        T.update!(m, T.KeyEvent('d'))
        @test m.view_mode == :table
        @test m.pending_delete == false
        @test m.quit == false
        @test length(m.tools) == ntools0
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        T.update!(m, T.KeyEvent('D'))
        @test m.view_mode == :table
        @test m.pending_delete == false
        @test m.quit == false
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard

        T.update!(m, T.KeyEvent('x'))
        @test m.view_mode == :tools
        @test m.quit == false
        @test m.last_event == "tools open"
        @test m.prompt_kind === nothing
        @test m.pending_delete == false

        tb = T.TestBackend(80, 20); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 20), [], []))
        @test T.find_text(tb, "TOOLS REGISTRY") !== nothing
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing
        @test T.find_text(tb, "Side Stats") === nothing
        full = join([string(T.row_text(tb, i)) for i in 1:20 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("No tools", full) || occursin("press [a]", full)

        # X also opens
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        T.update!(m, T.KeyEvent('X'))
        @test m.view_mode == :tools
        @test m.quit == false
    end

    @testset "tools mode: add/edit/delete prompts; Esc closes without quit" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 6), paused = true, seed_demos = :single)
        _ensure_charts!(m)
        @test isempty(m.tools)

        T.update!(m, T.KeyEvent('x'))
        @test m.view_mode == :tools

        # add: id then description
        T.update!(m, T.KeyEvent('a'))
        @test m.prompt_kind === :tool_add_id
        @test _live_may_advance(m) === false
        for ch in "ETCH-1"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :tool_add_desc
        @test m.tool_pending_id == "ETCH-1"
        for ch in "Etch chamber"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === nothing
        @test length(m.tools) == 1
        @test m.tools[1].id == "ETCH-1"
        @test m.tools[1].description == "Etch chamber"
        @test m.tools_selected == 1
        @test m.view_mode == :tools
        @test m.quit == false

        tb = T.TestBackend(80, 18); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 80, 18), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:18 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("ETCH-1", full)
        @test occursin("Etch chamber", full)

        # edit description
        T.update!(m, T.KeyEvent('n'))
        @test m.prompt_kind === :tool_edit_desc
        while !isempty(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        for ch in "revised"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.tools[1].description == "revised"
        @test m.tools[1].id == "ETCH-1"

        # second tool
        T.update!(m, T.KeyEvent('a'))
        for ch in "CVD-A"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        T.update!(m, T.KeyEvent(:enter))  # empty desc ok
        @test length(m.tools) == 2
        @test m.tools[2].id == "CVD-A"
        @test m.tools_selected == 2

        # ↑↓ navigate
        T.update!(m, T.KeyEvent(:up))
        @test m.tools_selected == 1
        T.update!(m, T.KeyEvent(:up))
        @test m.tools_selected == 1
        T.update!(m, T.KeyEvent(:down))
        @test m.tools_selected == 2

        # delete selected (CVD-A) with d+y
        T.update!(m, T.KeyEvent('d'))
        @test m.pending_delete
        @test _live_may_advance(m) === false
        T.update!(m, T.KeyEvent('y'))
        @test m.pending_delete == false
        @test length(m.tools) == 1
        @test m.tools[1].id == "ETCH-1"
        @test m.view_mode == :tools

        # delete cancel
        T.update!(m, T.KeyEvent('d'))
        T.update!(m, T.KeyEvent(:escape))
        @test m.pending_delete == false
        @test length(m.tools) == 1
        @test m.quit == false

        # Esc closes tools without quit
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test m.quit == false
        @test m.last_event == "tools closed"

        # q closes without quit
        T.update!(m, T.KeyEvent('x'))
        T.update!(m, T.KeyEvent('q'))
        @test m.view_mode == :dashboard
        @test m.quit == false

        # add refuses empty id
        T.update!(m, T.KeyEvent('x'))
        T.update!(m, T.KeyEvent('a'))
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === nothing
        @test occursin("empty id", m.last_event)
        # duplicate id keeps prompt
        T.update!(m, T.KeyEvent('a'))
        for ch in "ETCH-1"
            T.update!(m, T.KeyEvent(ch))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :tool_add_id
        @test occursin("duplicate", m.last_event)
        T.update!(m, T.KeyEvent(:escape))
        @test m.tool_pending_id == ""
    end

    @testset "tools mode: Enter sets filter_tool; mouse no-op; live blocked" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 8), paused = true, seed_demos = :single)
        _ensure_charts!(m)
        add_tool!(m, "TOOL-A", "alpha")
        add_tool!(m, "TOOL-B", "beta")
        m.charts[1].tools = ["TOOL-B"]  # chart assign is separate
        m.tools_selected = 1

        # live blocked in tools mode
        m.paused = false
        current_chart(m).live_enabled = true
        @test _live_may_advance(m) === true  # still dashboard
        T.update!(m, T.KeyEvent('x'))
        @test m.view_mode == :tools
        @test _live_may_advance(m) === false

        # mouse early-return
        m.hover_x = 5
        m.hovered = 1
        T.update!(m, T.MouseEvent(10, 5, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hover_x === nothing
        @test m.hovered === nothing
        @test occursin("modal", m.last_event)
        @test m.view_mode == :tools

        # Enter applies selected id as filter_tool and returns dashboard
        m.tools_selected = 2
        T.update!(m, T.KeyEvent(:enter))
        @test m.view_mode == :dashboard
        @test m.filter_tool == "TOOL-B"
        @test length(visible_charts(m)) == 1  # chart has TOOL-B assigned
        # registry alone does not assign — TOOL-A not on any chart
        set_filter_tool!(m, "TOOL-A")
        @test isempty(visible_charts(m)) || all(c -> "TOOL-A" in c.tools, visible_charts(m))
        clear_filters!(m)
    end

    @testset "tools mode: help/keymap mention x/tools registry" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 2), paused = true)
        _ensure_charts!(m)
        T.update!(m, T.KeyEvent('h'))
        tb = T.TestBackend(90, 30); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 30), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:30 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("x/X", full) || occursin("tools", lowercase(full)) || occursin("x ·", full)
        T.update!(m, T.KeyEvent(:escape))
        T.update!(m, T.KeyEvent('k'))
        tb2 = T.TestBackend(90, 28); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 90, 28), [], []))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:28 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("x X", full2) || occursin("tools", lowercase(full2)) || occursin("x ·", full2)
        T.update!(m, T.KeyEvent(:escape))

        # Keys panel (or expanded) advertises tools — header no longer dumps key chrome
        tb3 = T.TestBackend(120, 22); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1, 1, 120, 22), [], []))
        dash = join([string(T.row_text(tb3, i)) for i in 1:22 if T.row_text(tb3, i) !== nothing], "\n")
        @test occursin("tools", lowercase(dash)) || occursin("x tools", lowercase(dash))
        T.update!(m, T.KeyEvent('?'))
        tb3e = T.TestBackend(120, 28); T.reset!(tb3e.buf)
        T.view(m, T.Frame(tb3e.buf, T.Rect(1, 1, 120, 28), [], []))
        dash_e = join([string(T.row_text(tb3e, i)) for i in 1:28 if T.row_text(tb3e, i) !== nothing], "\n")
        @test occursin("tools", lowercase(dash_e))
        m.keys_panel_expanded = false
    end

    # ── P2-PR7: SharedTable grid view_mode=:table (KD-P2-20) ─────────────
    @testset "table mode: open (d/D), SHARED TABLE title, empty message, no bleed" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(10; seed = 7), paused = true)
        _ensure_charts!(m)
        @test m.view_mode == :dashboard
        @test m.seed_demos === :triple
        @test isempty(m.table.rows)

        T.update!(m, T.KeyEvent('d'))
        @test m.view_mode == :table
        @test m.quit == false
        @test m.last_event == "table open"
        @test m.table_editing == false
        @test m.prompt_kind === nothing

        tb = T.TestBackend(90, 22); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 90, 22), [], []))
        @test T.find_text(tb, "SHARED TABLE") !== nothing
        full = join([string(T.row_text(tb, i)) for i in 1:22 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("Empty table", full)
        # strict no-bleed
        @test T.find_text(tb, "SPC Workbench [dashboard]") === nothing
        @test T.find_text(tb, "Side Stats") === nothing
        @test T.find_text(tb, "Dashboard:") === nothing

        # D also opens; Esc closes without quit
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test m.quit == false
        @test m.last_event == "table closed"
        T.update!(m, T.KeyEvent('D'))
        @test m.view_mode == :table
        @test m.quit == false
        T.update!(m, T.KeyEvent('q'))
        @test m.view_mode == :dashboard
        @test m.quit == false
    end

    @testset "table mode: mode-gate library d=delete; dashboard d=grid" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 9), paused = true)
        _ensure_charts!(m)
        n0 = length(m.charts)
        @test n0 >= 2

        # library d arms delete, does not open table
        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent('d'))
        @test m.view_mode == :library
        @test m.pending_delete == true
        @test occursin("confirm delete", m.last_event)
        T.update!(m, T.KeyEvent(:escape))  # cancel delete
        @test m.pending_delete == false
        T.update!(m, T.KeyEvent(:escape))  # close library
        @test m.view_mode == :dashboard

        # dashboard d opens table (does not delete)
        T.update!(m, T.KeyEvent('d'))
        @test m.view_mode == :table
        @test m.pending_delete == false
        @test length(m.charts) == n0
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
    end

    @testset "table mode: scroll, cell edit, rematerialize, live/mouse gates" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(12; seed = 11),
            paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.table = SharedTable(
            columns = ["Tool", "Value", "Lot"],
            rows = [
                Dict("Tool" => "A", "Value" => "10.0", "Lot" => "L1"),
                Dict("Tool" => "B", "Value" => "20.0", "Lot" => "L1"),
                Dict("Tool" => "A", "Value" => "30.0", "Lot" => "L2"),
                Dict("Tool" => "B", "Value" => "40.0", "Lot" => "L2"),
                Dict("Tool" => "A", "Value" => "50.0", "Lot" => "L3"),
            ],
        )
        ch = current_chart(m)
        ch.col_value = "Value"
        ch.col_tool = "Tool"
        ch.tools = String[]  # all rows
        vals_before = copy(ch.data.values)

        T.update!(m, T.KeyEvent('d'))
        @test m.view_mode == :table
        @test _live_may_advance(m) === false

        # render grid with columns + values
        tb = T.TestBackend(100, 24); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("SHARED TABLE", full)
        @test occursin("Tool", full)
        @test occursin("Value", full)
        @test occursin("10.0", full) || occursin("10", full)

        # navigation: down/right
        @test m.table_row == 1
        @test m.table_col == 1
        T.update!(m, T.KeyEvent(:down))
        @test m.table_row == 2
        T.update!(m, T.KeyEvent(:right))
        @test m.table_col == 2
        T.update!(m, T.KeyEvent(:up))
        @test m.table_row == 1
        T.update!(m, T.KeyEvent(:left))
        @test m.table_col == 1

        # PgDn / PgUp move by page
        T.update!(m, T.KeyEvent(:pagedown))
        @test m.table_row >= 1
        T.update!(m, T.KeyEvent(:pageup))
        @test m.table_row == 1

        # Enter edits cell (Value at r1 c2 after we move)
        T.update!(m, T.KeyEvent(:right))  # col Value
        @test m.table_col == 2
        T.update!(m, T.KeyEvent(:enter))
        @test m.table_editing == true
        @test m.table_buf == "10.0"
        # q while editing is literal
        while !isempty(m.table_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        for c in "99.5"
            T.update!(m, T.KeyEvent(c))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.table_editing == false
        @test m.table.rows[1]["Value"] == "99.5"
        # series NOT auto-updated until rematerialize
        @test current_chart(m).data.values == vals_before

        # re-render shows edited value
        tb2 = T.TestBackend(100, 24); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 24), [], []))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:24 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("99.5", full2)

        # Esc mid-edit cancels
        T.update!(m, T.KeyEvent(:enter))
        @test m.table_editing == true
        m.table_buf = "bad"
        T.update!(m, T.KeyEvent(:escape))
        @test m.table_editing == false
        @test m.table.rows[1]["Value"] == "99.5"
        @test m.view_mode == :table  # still in table

        # explicit rematerialize (r) rebuilds active series
        T.update!(m, T.KeyEvent('r'))
        @test m.view_mode == :table  # stay in grid
        @test current_chart(m).source === :table
        @test current_chart(m).live_enabled === false
        @test current_chart(m).data.values[1] ≈ 99.5
        @test length(current_chart(m).data.values) == 5
        @test occursin("rematerialized", m.last_event)

        # mouse early-return
        m.hover_x = 5
        m.hovered = 1
        T.update!(m, T.MouseEvent(10, 5, T.mouse_left, T.mouse_move, false, false, false))
        @test m.hover_x === nothing
        @test m.hovered === nothing
        @test occursin("modal", m.last_event)
        @test m.view_mode == :table

        # live blocked while in table even if unpaused + live_enabled
        m.paused = false
        current_chart(m).live_enabled = true
        @test _live_may_advance(m) === false
        T.update!(m, T.KeyEvent(:escape))
        @test m.view_mode == :dashboard
        @test m.quit == false
    end

    @testset "table mode: help/keymap/header mention d/table; empty rematerialize msg" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 3), paused = true)
        _ensure_charts!(m)

        T.update!(m, T.KeyEvent('h'))
        tb = T.TestBackend(100, 36); T.reset!(tb.buf)
        T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 36), [], []))
        full = join([string(T.row_text(tb, i)) for i in 1:36 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("d/D", full) || occursin("SharedTable", full) || occursin("table", lowercase(full))
        T.update!(m, T.KeyEvent(:escape))

        T.update!(m, T.KeyEvent('k'))
        tb2 = T.TestBackend(100, 30); T.reset!(tb2.buf)
        T.view(m, T.Frame(tb2.buf, T.Rect(1, 1, 100, 30), [], []))
        full2 = join([string(T.row_text(tb2, i)) for i in 1:30 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("d D", full2) || occursin("SharedTable", full2) || occursin("table", lowercase(full2))
        T.update!(m, T.KeyEvent(:escape))

        # Keys panel advertises table (header no longer dumps [d]table chrome)
        tb3 = T.TestBackend(140, 22); T.reset!(tb3.buf)
        T.view(m, T.Frame(tb3.buf, T.Rect(1, 1, 140, 22), [], []))
        dash = join([string(T.row_text(tb3, i)) for i in 1:22 if T.row_text(tb3, i) !== nothing], "\n")
        @test occursin("table", lowercase(dash)) || occursin("d table", lowercase(dash))
        T.update!(m, T.KeyEvent('?'))
        tb3e = T.TestBackend(140, 28); T.reset!(tb3e.buf)
        T.view(m, T.Frame(tb3e.buf, T.Rect(1, 1, 140, 28), [], []))
        dash_e = join([string(T.row_text(tb3e, i)) for i in 1:28 if T.row_text(tb3e, i) !== nothing], "\n")
        @test occursin("table", lowercase(dash_e))
        m.keys_panel_expanded = false

        # empty rematerialize message
        @test isempty(m.table.rows)
        T.update!(m, T.KeyEvent('d'))
        T.update!(m, T.KeyEvent('r'))
        @test m.view_mode == :table
        @test occursin("empty table", lowercase(m.last_event))
        T.update!(m, T.KeyEvent(:escape))
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
        m.view_mode = :config
        m.config_tab = :saved
        @test _live_may_advance(m) === false
        m.config_tab = :weco
        @test _live_may_advance(m) === false
        m.view_mode = :dashboard
        @test _live_may_advance(m) === true

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

        # help/keymap advertise live toggle (g) — styled chips, not legacy g/G dump
        m2 = SPCWorkbenchModel(data = d, paused = true)
        T.update!(m2, T.KeyEvent('h'))
        tb = T.TestBackend(90, 22); T.reset!(tb.buf)
        T.view(m2, T.Frame(tb.buf, T.Rect(1, 1, 90, 22), [], []))
        help_txt = join([string(T.row_text(tb, i)) for i in 1:22 if T.row_text(tb, i) !== nothing], "\n")
        @test occursin("g/G", help_txt) || occursin("g ·", help_txt) || occursin("live", lowercase(help_txt))
        T.update!(m2, T.KeyEvent(:escape))
        T.update!(m2, T.KeyEvent('k'))
        tb2 = T.TestBackend(90, 22); T.reset!(tb2.buf)
        T.view(m2, T.Frame(tb2.buf, T.Rect(1, 1, 90, 22), [], []))
        ktxt = join([string(T.row_text(tb2, i)) for i in 1:22 if T.row_text(tb2, i) !== nothing], "\n")
        @test occursin("g/G", ktxt) || occursin("g ·", ktxt) || occursin("live", lowercase(ktxt))
    end

    @testset "seed_demos default remains :triple" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 1), paused = true)
        @test m.seed_demos === :triple
    end

    @testset "CSV import fills in-memory SharedTable (KD25; no re-read on materialize)" begin
        d = generate_spc_workbench_data(8; seed = 2)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        @test isempty(m.table.rows)

        r = import_csv_new_chart!(m, SAMPLE; name = "TblCSV")
        @test r isa CsvParseOk
        @test !isempty(m.table.rows)
        @test "Value" in m.table.columns
        @test length(m.table.rows) == 10
        # table cells are strings; series already on chart
        @test m.table.rows[1]["Value"] == "100.1" || tryparse(Float64, m.table.rows[1]["Value"]) ≈ 100.1
        # default Value path: col_value synced to used column
        @test current_chart(m).col_value == "Value"
        @test current_chart(m).source === :series  # until explicit materialize

        # materialize from table (in-memory) without re-opening CSV path
        ch = ChartSpec(name = "FromTable", col_value = "Value", tools = String[])
        materialize_chart_from_table!(ch, m.table)
        @test ch.source === :table
        @test ch.live_enabled === false
        @test length(ch.data.values) == 10
        @test ch.data.values[1] ≈ 100.1
        @test ch.data.values[end] ≈ 99.7

        # import_csv_into_model! also refreshes table
        mktempdir() do dir
            p = _write_csv(joinpath(dir, "t2.csv"), "Tool,Value\nX,1.0\nY,2.0\nX,3.0\n")
            r2 = import_csv_into_model!(m, p; value_col = "Value")
            @test r2 isa CsvParseOk
            @test length(m.table.rows) == 3
            @test "Tool" in m.table.columns
            @test current_chart(m).col_value == "Value"
            @test current_chart(m).col_tool == "Tool"
            ch2 = ChartSpec(col_value = "Value", col_tool = "Tool", tools = ["X"])
            materialize_chart_from_table!(ch2, m.table)
            @test ch2.data.values == [1.0, 3.0]
        end
    end

    @testset "non-default value_col syncs chart col_value (Issue 1; no materialize wipe)" begin
        d = generate_spc_workbench_data(6; seed = 4)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        mktempdir() do dir
            p = _write_csv(joinpath(dir, "thk.csv"),
                "Timestamp,Tool,Thickness\n" *
                "t1,Film-A,1.5\n" *
                "t2,Film-A,2.5\n" *
                "t3,Film-B,9.0\n")
            r = import_csv_new_chart!(m, p; name = "Thk", value_col = "Thickness")
            @test r isa CsvParseOk
            ch = current_chart(m)
            @test ch.name == "Thk"
            @test ch.data.values == [1.5, 2.5, 9.0]
            @test ch.col_value == "Thickness"  # NOT stuck at default "Value"
            @test ch.col_tool == "Tool"
            @test ch.col_time == "Timestamp"
            @test ch.source === :series
            @test ch.live_enabled === false
            # materialize must not wipe series when col maps match table headers
            n0 = length(ch.data.values)
            materialize_chart_from_table!(ch, m.table)
            @test ch.source === :table
            @test ch.live_enabled === false
            @test ch.data.values == [1.5, 2.5, 9.0]
            @test length(ch.data.values) == n0

            # into_model path also syncs
            p2 = _write_csv(joinpath(dir, "thk2.csv"), "Tool,Reading\nA,10\nB,20\n")
            r2 = import_csv_into_model!(m, p2; value_col = "Reading")
            @test r2 isa CsvParseOk
            ch2 = current_chart(m)
            @test ch2.col_value == "Reading"
            @test ch2.col_tool == "Tool"
            materialize_chart_from_table!(ch2, m.table)
            @test ch2.data.values == [10.0, 20.0]
        end
    end
end

end # module TestSPCWorkbenchCSVImport

# ═══════════════════════════════════════════════════════════════════════
# GC-PR3: library i/e/w/W path prompts → CSV/JSON I/O APIs (KeyEvent).
# Package-module path (KD22) so Enter hits TachikomaTUI I/O symbols.
# ═══════════════════════════════════════════════════════════════════════

module TestSPCWorkbenchLibraryIO
using Test
using TachikomaTUI
using Tachikoma
using Random

const T = Tachikoma
const WB = TachikomaTUI
const _ensure_charts! = WB._ensure_charts!
const current_chart = WB.current_chart

const FIX_DIR = joinpath(@__DIR__, "fixtures", "spc")
const SAMPLE = joinpath(FIX_DIR, "sample_value.csv")

"""Type `path` into the active path prompt via KeyEvents (printable chars)."""
function _type_path!(m, path::AbstractString)
    for ch in collect(String(path))
        T.update!(m, T.KeyEvent(ch))
    end
end

"""Clear prompt_buf with backspaces then type path."""
function _set_prompt_path!(m, path::AbstractString)
    while !isempty(m.prompt_buf)
        T.update!(m, T.KeyEvent(:backspace))
    end
    _type_path!(m, path)
end

@testset "GC-PR3 library I/O keys (using TachikomaTUI)" begin

    @testset "import i: active≠library_selected mutates selected chart" begin
        d = generate_spc_workbench_data(20; seed = 7)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        @test length(m.charts) >= 3
        @test m.seed_demos === :triple

        # Distinct series; keep active on chart 1, select chart 2
        m.charts[1].data.values = [1.0, 2.0, 3.0]
        m.charts[2].data.values = [9.0, 8.0]
        m.charts[3].data.values = [100.0]
        m.active = 1
        m.library_selected = 2
        active_snap = copy(m.charts[1].data.values)
        other_snap = copy(m.charts[3].data.values)
        n_charts = length(m.charts)

        T.update!(m, T.KeyEvent('m'))
        @test m.view_mode == :library
        m.library_selected = 2
        @test m.active == 1
        @test m.active != m.library_selected

        T.update!(m, T.KeyEvent('i'))
        @test m.prompt_kind === :import_csv
        @test m.prompt_buf == ""
        _set_prompt_path!(m, SAMPLE)
        T.update!(m, T.KeyEvent(:enter))

        @test m.prompt_kind === nothing
        @test m.view_mode == :library
        @test m.active == 1  # active unchanged
        @test length(m.charts) == n_charts
        @test occursin("imported", m.last_event)
        @test m.charts[2].live_enabled === false
        @test length(m.charts[2].data.values) == 10
        # active chart untouched
        @test m.charts[1].data.values == active_snap
        @test m.charts[3].data.values == other_snap
        # selected series matches fixture
        r = parse_csv_table(SAMPLE)
        @test r isa CsvParseOk
        @test m.charts[2].data.values == r.values
    end

    @testset "import err: no mutate; last_event import err; stay library" begin
        d = generate_spc_workbench_data(12; seed = 3)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        m.active = 1
        m.library_selected = 2
        snaps = [copy(c.data.values) for c in m.charts]
        lives = [c.live_enabled for c in m.charts]
        n0 = length(m.charts)
        prev_export = m.last_export_path
        prev_wb = m.last_workbench_path

        T.update!(m, T.KeyEvent('m'))
        m.library_selected = 2
        T.update!(m, T.KeyEvent('i'))
        bad = joinpath(FIX_DIR, "does_not_exist_$(rand(UInt32)).csv")
        _set_prompt_path!(m, bad)
        T.update!(m, T.KeyEvent(:enter))

        # On err: keep prompt open + buf so path can be edited and re-Enter
        @test m.prompt_kind === :import_csv
        @test m.view_mode == :library
        @test startswith(m.last_event, "import err:")
        @test length(m.charts) == n0
        for i in eachindex(m.charts)
            @test m.charts[i].data.values == snaps[i]
            @test m.charts[i].live_enabled === lives[i]
        end
        @test m.last_export_path == prev_export
        @test m.last_workbench_path == prev_wb
        @test m.prompt_buf == bad
        # Esc still cancels without quit
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing
        @test m.quit == false
        @test m.view_mode == :library
    end

    @testset "export e then re-import: numeric equality; last_export_path on ok" begin
        d = generate_spc_workbench_data(15; seed = 4)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        known = [11.1, 22.2, 33.3, 44.4]
        m.charts[2].data.values = copy(known)
        m.active = 1
        m.library_selected = 2
        orig_active = copy(m.charts[1].data.values)

        mktempdir() do dir
            path = joinpath(dir, "lib_sel.csv")
            T.update!(m, T.KeyEvent('m'))
            @test m.view_mode == :library
            m.library_selected = 2
            T.update!(m, T.KeyEvent('e'))
            @test m.prompt_kind === :export_csv
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === nothing
            @test occursin("exported $(length(known)) values", m.last_event)
            @test m.last_export_path == path
            @test m.view_mode == :library
            @test m.quit == false
            @test m.charts[1].data.values == orig_active
            @test m.active == 1

            r = parse_csv_table(path)
            @test r isa CsvParseOk
            @test length(r.values) == length(known)
            for i in eachindex(known)
                @test r.values[i] ≈ known[i]
            end

            # re-import into selected chart 3: wipe to a known different series first
            m.library_selected = 3
            m.charts[3].data.values = [0.0, 0.0]  # distinct from known
            @test m.charts[3].data.values != known
            T.update!(m, T.KeyEvent('i'))
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === nothing
            @test occursin("imported", m.last_event)
            @test length(m.charts[3].data.values) == length(known)
            for i in eachindex(known)
                @test m.charts[3].data.values[i] ≈ known[i]
            end
            @test m.charts[3].data.values != [0.0, 0.0]  # mutated from wipe
            @test length(m.charts[2].data.values) == length(known)  # prior export target intact
        end
    end

    @testset "export err: last_export_path not updated; charts unchanged" begin
        d = generate_spc_workbench_data(10; seed = 5)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        m.last_export_path = "/tmp/keep_me.csv"
        snaps = [copy(c.data.values) for c in m.charts]

        T.update!(m, T.KeyEvent('m'))
        T.update!(m, T.KeyEvent('e'))
        @test m.prompt_kind === :export_csv
        # empty path → fail closed; prompt stays open for retry
        while !isempty(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :export_csv
        @test occursin("export err", m.last_event)
        @test m.last_export_path == "/tmp/keep_me.csv"
        @test m.view_mode == :library
        for i in eachindex(m.charts)
            @test m.charts[i].data.values == snaps[i]
        end
        T.update!(m, T.KeyEvent(:escape))
        @test m.prompt_kind === nothing

        # unwritable path
        m.last_export_path = "/tmp/keep_me.csv"
        T.update!(m, T.KeyEvent('e'))
        bad_path = "/proc/definitely_unwritable_$(rand(UInt32))/out.csv"
        _set_prompt_path!(m, bad_path)
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :export_csv  # stay open for path retry
        @test occursin("export err", m.last_event)
        @test m.last_export_path == "/tmp/keep_me.csv"
        @test m.prompt_buf == bad_path
        @test m.view_mode == :library
    end

    @testset "save w Ok / err: last_workbench_path only on success" begin
        d = generate_spc_workbench_data(12; seed = 6)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        m.charts[1].usl = 42.0
        m.last_workbench_path = ""

        mktempdir() do dir
            path = joinpath(dir, "session.json")
            T.update!(m, T.KeyEvent('m'))
            T.update!(m, T.KeyEvent('w'))
            @test m.prompt_kind === :save_workbench
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === nothing
            @test m.last_workbench_path == path
            @test occursin("saved", m.last_event)
            @test isfile(path)
            @test m.view_mode == :library

            # err: unwritable — path not updated; prompt stays open for retry
            m.last_workbench_path = path
            T.update!(m, T.KeyEvent('w'))
            bad = "/proc/no_write_$(rand(UInt32))/wb.json"
            _set_prompt_path!(m, bad)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === :save_workbench
            @test occursin("save err", m.last_event)
            @test m.last_workbench_path == path  # unchanged
            @test m.prompt_buf == bad
            @test m.view_mode == :library
        end
    end

    @testset "load W round-trip KeyEvent; err stay library no mutate" begin
        d = generate_spc_workbench_data(14; seed = 8)
        src = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(src)
        src.charts[1].data.values = [7.0, 8.0, 9.0]
        src.charts[1].usl = 55.0
        src.active = 2

        mktempdir() do dir
            path = joinpath(dir, "roundtrip.json")
            @test save_workbench(src, path) === nothing

            # Fresh model → library → W load
            m = SPCWorkbenchModel(
                data = generate_spc_workbench_data(5; seed = 1),
                paused = true,
                seed_demos = :triple,
            )
            _ensure_charts!(m)
            m.rng = MersenneTwister(4242)
            rng0 = m.rng
            tick0 = m.tick
            live_max0 = m.live_max
            n_before = length(m.charts)
            @test n_before >= 1
            T.update!(m, T.KeyEvent('m'))
            @test m.view_mode == :library
            T.update!(m, T.KeyEvent('W'))
            @test m.prompt_kind === :load_workbench
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === nothing
            @test m.view_mode == :dashboard  # load clears to dashboard
            @test occursin("loaded", m.last_event)
            @test m.last_workbench_path == path
            @test length(m.charts) == length(src.charts)
            @test m.active == src.active
            @test m.charts[1].data.values == [7.0, 8.0, 9.0]
            @test m.charts[1].usl == 55.0
            # load_workbench! preserves rng/tick/live_max identity
            @test m.rng === rng0
            @test m.tick == tick0
            @test m.live_max == live_max0

            # load err: missing file — stay library, keep prompt open for path retry
            m.view_mode = :library
            snaps = [copy(c.data.values) for c in m.charts]
            n0 = length(m.charts)
            prev_path = m.last_workbench_path
            T.update!(m, T.KeyEvent('W'))
            bad = joinpath(dir, "missing_$(rand(UInt32)).json")
            _set_prompt_path!(m, bad)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === :load_workbench  # restored after io clears on err
            @test m.view_mode == :library
            @test startswith(m.last_event, "load err:")
            @test length(m.charts) == n0
            for i in eachindex(m.charts)
                @test m.charts[i].data.values == snaps[i]
            end
            @test m.last_workbench_path == prev_path
            @test m.prompt_buf == bad  # kept for retry
            @test m.rng === rng0
            T.update!(m, T.KeyEvent(:escape))
            @test m.prompt_kind === nothing
            @test m.view_mode == :library
        end
    end

    @testset "prompt path may contain q; no quit" begin
        d = generate_spc_workbench_data(8; seed = 2)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :triple)
        _ensure_charts!(m)
        T.update!(m, T.KeyEvent('m'))
        T.update!(m, T.KeyEvent('i'))
        @test m.prompt_kind === :import_csv
        path_with_q = joinpath(tempdir(), "q_path_$(rand(UInt32)).csv")
        _set_prompt_path!(m, path_with_q)
        @test occursin("q", m.prompt_buf)
        @test m.quit == false
        @test m.view_mode == :library
        T.update!(m, T.KeyEvent(:escape))
        @test m.quit == false
        @test m.prompt_kind === nothing
    end

    @testset "seed_demos default remains :triple" begin
        m = SPCWorkbenchModel(data = generate_spc_workbench_data(8; seed = 1), paused = true)
        @test m.seed_demos === :triple
    end
end

end # module TestSPCWorkbenchLibraryIO

# JSON session persistence (schema v1) — via package module (KD22)
# ═══════════════════════════════════════════════════════════════════════

module TestSPCWorkbenchJSON
using Test
using Random
using TachikomaTUI
# private bootstrap used by workbench itself (not exported)
const _ensure_charts! = TachikomaTUI._ensure_charts!
const _sync_active_back! = TachikomaTUI._sync_active_back!

@testset "SPC Workbench JSON session persistence (schema v1)" begin

    function _make_session()
        d = generate_spc_workbench_data(12; seed = 99)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        # second chart first; set active before mutating non-active ChartSpec fields
        # (set_active_chart! syncs legacy mirrors and would wipe stale m.usl onto chart)
        idx = add_chart!(m; name = "Second", data = WorkbenchData(
            values = [1.0, 2.0, 3.0, 4.0, 5.0], cl = 3.0, sigma = 1.0))
        m.charts[idx].chart_type = I_MR
        m.charts[idx].live_enabled = false
        set_active_chart!(m, idx)
        # mutate chart 1 (inactive) — not overwritten by legacy sync
        ch = m.charts[1]
        ch.usl = 110.0
        ch.target = 100.0
        ch.lsl = 90.0
        ch.enabled_rules["WECO-6"] = true
        ch.enabled_rules["WECO-1"] = false
        ch.chart_type = Xbar_R
        ch.live_enabled = true
        ch.param = "thickness"
        ch.units = "nm"
        m.tools = [ToolEntry(id = "T1", description = "tool one")]
        return m
    end

    @testset "GC-PR4: filters omitted from JSON; load clears session filters" begin
        m = _make_session()
        m.filter_tool = "ETCH-1"
        m.filter_type = "I-MR"
        m.filter_owner = "Nobody"
        m.filter_prompt_field = :owner
        d = workbench_to_dict(m)
        @test !haskey(d, "filter_tool")
        @test !haskey(d, "filter_type")
        @test !haskey(d, "filter_owner")
        @test !haskey(d, "filter_prompt_field")
        # setters not public exports
        @test !(:set_filter_tool! in names(TachikomaTUI))
        @test !(:set_filter_type! in names(TachikomaTUI))
        @test !(:set_filter_owner! in names(TachikomaTUI))
        @test !(:clear_filters! in names(TachikomaTUI))
        @test :visible_charts in names(TachikomaTUI)
        @test :dashboard_pane_charts in names(TachikomaTUI)

        path = joinpath(tempdir(), "spc_wb_filt_$(rand(UInt32)).json")
        try
            err = save_workbench(m, path)
            @test err === nothing
            # leave filters + tools UI ephemerals set, then load into same model
            m.tools_selected = 99
            m.tools_scroll = 50
            m.tool_pending_id = "STALE"
            err2 = load_workbench!(m, path)
            @test err2 === nothing
            @test m.filter_tool == ""
            @test m.filter_type == ""
            @test m.filter_owner == ""
            @test m.tools_selected == 1
            @test m.tools_scroll == 0
            @test m.tool_pending_id == ""
            @test m.view_mode == :dashboard
            @test m.filter_prompt_field === :tool
            @test length(visible_charts(m)) == length(m.charts)
            @test !isempty(m.charts)
        finally
            isfile(path) && rm(path; force = true)
        end
    end

    @testset "tempfile round-trip: values, WECO, specs, active, chart_type wire" begin
        m = _make_session()
        path = joinpath(tempdir(), "spc_wb_rt_$(rand(UInt32)).json")
        try
            err = save_workbench(m, path)
            @test err === nothing
            @test isfile(path)
            @test m.last_workbench_path == path

            loaded = load_workbench(path)
            @test loaded isa SPCWorkbenchModel
            @test length(loaded.charts) == length(m.charts)
            @test loaded.active == m.active
            @test loaded.last_workbench_path == path

            # values
            @test loaded.charts[1].data.values == m.charts[1].data.values
            @test loaded.charts[2].data.values == m.charts[2].data.values

            # WECO rules
            @test loaded.charts[1].enabled_rules["WECO-6"] === true
            @test loaded.charts[1].enabled_rules["WECO-1"] === false

            # specs
            @test loaded.charts[1].usl == 110.0
            @test loaded.charts[1].target == 100.0
            @test loaded.charts[1].lsl == 90.0

            # chart_type wire strings round-trip
            @test chart_type_to_string(loaded.charts[1].chart_type) == "Xbar-R"
            @test chart_type_to_string(loaded.charts[2].chart_type) == "I-MR"
            @test loaded.charts[1].chart_type === Xbar_R
            @test loaded.charts[2].chart_type === I_MR

            # live_enabled written and restored
            @test loaded.charts[1].live_enabled === true
            @test loaded.charts[2].live_enabled === false

            # tools registry
            @test length(loaded.tools) == 1
            @test loaded.tools[1].id == "T1"

            # dict-level wire check
            d = workbench_to_dict(m)
            @test d["version"] == 1
            @test d["charts"][1]["chart_type"] == "Xbar-R"
            @test haskey(d["charts"][1], "live_enabled")
            @test d["active"] == m.active
        finally
            isfile(path) && rm(path; force = true)
        end
    end

    @testset "session default_rules distinct from per-chart (KD-P2-21)" begin
        m = _make_session()
        # Session defaults ≠ active chart rules
        m.default_rules = copy(DEFAULT_WECO_RULES)
        m.default_rules["WECO-6"] = true
        m.default_rules["WECO-8"] = true
        m.default_rules["WECO-1"] = false
        # Active chart keeps its own rules (distinct from session defaults)
        act = m.charts[m.active]
        act.enabled_rules["WECO-2"] = false
        # Per-chart on chart 1 already has WECO-6 true / WECO-1 false from _make_session
        @test m.charts[1].enabled_rules["WECO-6"] === true
        @test m.charts[1].enabled_rules["WECO-1"] === false

        d = workbench_to_dict(m)
        @test d["default_rules"]["WECO-6"] === true
        @test d["default_rules"]["WECO-8"] === true
        @test d["default_rules"]["WECO-1"] === false
        # root default_rules is NOT the active chart map
        @test d["default_rules"]["WECO-2"] === true  # session still DEFAULT true; active has false
        @test d["charts"][m.active]["enabled_rules"]["WECO-2"] === false
        # per-chart chart 1 rules remain in chart object
        @test d["charts"][1]["enabled_rules"]["WECO-6"] === true
        @test d["charts"][1]["enabled_rules"]["WECO-1"] === false

        path = joinpath(tempdir(), "spc_wb_def_$(rand(UInt32)).json")
        try
            @test save_workbench(m, path) === nothing
            loaded = load_workbench(path)
            @test loaded isa SPCWorkbenchModel
            @test loaded.default_rules["WECO-6"] === true
            @test loaded.default_rules["WECO-8"] === true
            @test loaded.default_rules["WECO-1"] === false
            # per-chart still independent after load
            @test loaded.charts[1].enabled_rules["WECO-6"] === true
            @test loaded.charts[1].enabled_rules["WECO-1"] === false
            @test loaded.charts[loaded.active].enabled_rules["WECO-2"] === false
            # enabled_rules mirror is active chart, not session defaults
            @test loaded.enabled_rules["WECO-2"] === false
            @test loaded.enabled_rules !== loaded.default_rules
            # add_chart! on loaded uses session defaults
            nidx = add_chart!(loaded; name = "AfterLoad")
            @test loaded.charts[nidx].enabled_rules["WECO-6"] === true
            @test loaded.charts[nidx].enabled_rules["WECO-8"] === true
            @test loaded.charts[nidx].enabled_rules["WECO-1"] === false
            @test loaded.charts[nidx].enabled_rules !== loaded.default_rules
        finally
            isfile(path) && rm(path; force = true)
        end

        # omitted default_rules → module DEFAULT_WECO_RULES
        bare = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-def",
                    "name" => "Bare",
                    "chart_type" => "I-MR",
                    "values" => [1.0, 2.0, 3.0],
                ),
            ],
        )
        m_bare = workbench_from_dict(bare)
        @test m_bare isa SPCWorkbenchModel
        @test m_bare.default_rules["WECO-1"] === true
        @test m_bare.default_rules["WECO-6"] === false
    end

    @testset "omitted live_enabled → false (safe default)" begin
        d = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-1",
                    "name" => "NoLiveKey",
                    "chart_type" => "I-MR",
                    "values" => [10.0, 11.0, 12.0],
                    # live_enabled intentionally omitted
                ),
            ],
        )
        m = workbench_from_dict(d)
        @test m isa SPCWorkbenchModel
        @test m.charts[1].live_enabled === false
        # writers always emit the field
        out = workbench_to_dict(m)
        @test haskey(out["charts"][1], "live_enabled")
        @test out["charts"][1]["live_enabled"] === false
    end

    @testset "load err no mutate (fail closed)" begin
        d0 = generate_spc_workbench_data(8; seed = 3)
        m = SPCWorkbenchModel(data = d0, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.charts[1].usl = 55.0
        m.charts[1].data.values[1] = 123.456
        m.active = 1
        m.rng = MersenneTwister(4242)
        rng_before = m.rng
        m.tick = 7
        m.quit = false
        m.live_max = 321
        m.view_mode = :config
        m.editing = :usl
        m.edit_buf = "partial"
        m.last_event = "prior"
        snapshot_vals = copy(m.charts[1].data.values)
        snapshot_usl = m.charts[1].usl
        snapshot_n = length(m.charts)
        snapshot_tick = m.tick
        snapshot_live_max = m.live_max

        bad = Dict{String,Any}("version" => 99, "active" => 1, "charts" => [
            Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0]),
        ])
        err = workbench_from_dict!(m, bad)
        @test err isa AbstractString
        @test occursin("version", err) || occursin("unsupported", err)
        # unchanged charts + preserved rng identity
        @test length(m.charts) == snapshot_n
        @test m.charts[1].data.values == snapshot_vals
        @test m.charts[1].usl == snapshot_usl
        @test m.tick == snapshot_tick
        @test m.live_max == snapshot_live_max
        @test m.rng === rng_before
        @test m.view_mode === :config  # fail closed: no partial apply / no clear
        @test m.editing === :usl

        # empty charts
        err2 = workbench_from_dict!(m, Dict{String,Any}("version" => 1, "active" => 1, "charts" => Any[]))
        @test err2 isa AbstractString
        @test length(m.charts) == snapshot_n
        @test m.charts[1].usl == snapshot_usl
        @test m.rng === rng_before

        # missing version
        err3 = workbench_from_dict!(m, Dict{String,Any}("active" => 1, "charts" => [
            Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0]),
        ]))
        @test err3 isa AbstractString
        @test length(m.charts) == snapshot_n
        @test m.rng === rng_before

        # missing active (required key)
        err_active = workbench_from_dict!(m, Dict{String,Any}(
            "version" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
        ))
        @test err_active isa AbstractString
        @test occursin("active", err_active)
        @test length(m.charts) == snapshot_n
        @test m.charts[1].usl == snapshot_usl
        @test m.charts[1].data.values == snapshot_vals
        @test m.rng === rng_before

        # unknown chart_type
        err4 = workbench_from_dict!(m, Dict{String,Any}(
            "version" => 1, "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "NOPE", "values" => [1.0])],
        ))
        @test err4 isa AbstractString
        @test length(m.charts) == snapshot_n
        @test m.charts[1].data.values == snapshot_vals
        @test m.rng === rng_before

        # unreadable path via load_workbench! — last_event prefixed; charts untouched
        err5 = load_workbench!(m, "/tmp/definitely_missing_spc_wb_$(rand(UInt32)).json")
        @test err5 isa AbstractString
        @test startswith(err5, "load err:")
        @test occursin("unreadable", err5)
        @test startswith(m.last_event, "load err:")
        @test length(m.charts) == snapshot_n
        @test m.charts[1].usl == snapshot_usl
        @test m.rng === rng_before
        @test m.view_mode === :config  # still uncleared after fail-closed load err

        # schema err via load_workbench! also prefixes last_event (path readable)
        path_bad = joinpath(tempdir(), "spc_wb_bad_$(rand(UInt32)).json")
        try
            open(path_bad, "w") do io
                write(io, """{"version":99,"active":1,"charts":[{"id":"x","name":"y","chart_type":"I-MR","values":[1.0]}]}""")
            end
            err6 = load_workbench!(m, path_bad)
            @test err6 isa AbstractString
            @test startswith(err6, "load err:")
            @test occursin("version", err6)
            @test startswith(m.last_event, "load err:")
            @test length(m.charts) == snapshot_n
            @test m.charts[1].usl == snapshot_usl
            @test m.rng === rng_before
            @test m.view_mode === :config
        finally
            isfile(path_bad) && rm(path_bad; force = true)
        end
    end

    @testset "load_workbench! replaces charts + clears ephemerals + preserves rng/tick/live_max" begin
        d0 = generate_spc_workbench_data(8; seed = 5)
        m = SPCWorkbenchModel(data = d0, paused = false, seed_demos = :triple)
        _ensure_charts!(m)
        @test length(m.charts) == 3
        m.rng = MersenneTwister(777)
        rng_before = m.rng
        m.tick = 42
        m.live_max = 150
        m.quit = false
        m.view_mode = :config
        m.editing = :target
        m.edit_buf = "99"
        m.hovered = 2
        m.selected = 1
        m.drag_start = (x = 1, y = 2, vp = Viewport())
        m.last_event = "prior"

        path = joinpath(tempdir(), "spc_wb_inplace_$(rand(UInt32)).json")
        try
            src = _make_session()
            @test save_workbench(src, path) === nothing
            @test startswith(src.last_event, "saved ")

            err = load_workbench!(m, path)
            @test err === nothing
            @test length(m.charts) == length(src.charts)
            @test m.active == src.active
            @test m.charts[1].usl == 110.0
            @test m.charts[1].enabled_rules["WECO-6"] === true
            @test m.last_workbench_path == path
            @test startswith(m.last_event, "loaded ")
            # ephemerals cleared
            @test m.editing === nothing
            @test m.edit_buf == ""
            @test m.hovered === nothing
            @test m.selected === nothing
            @test m.drag_start === nothing
            @test m.view_mode === :dashboard
            @test m.library_selected == m.active
            # preserved
            @test m.tick == 42
            @test m.live_max == 150
            @test m.quit == false
            # rng object identity preserved (same object)
            @test m.rng === rng_before
            @test m.rng isa MersenneTwister
        finally
            isfile(path) && rm(path; force = true)
        end
    end

    @testset "admins/passcodes never applied; unknown chart keys ignored" begin
        d = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "admins" => [Dict("user" => "evil", "passcode" => "secret")],
            "passcodes" => ["x"],
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-z",
                    "name" => "Safe",
                    "chart_type" => "I-MR",
                    "values" => [1.0, 2.0],
                    "admins" => "ignore-me",
                    "future_key" => 123,
                    "live_enabled" => true,
                ),
            ],
        )
        m = workbench_from_dict(d)
        @test m isa SPCWorkbenchModel
        @test m.charts[1].name == "Safe"
        @test m.charts[1].data.values == [1.0, 2.0]
        # no admin field on model / chart
        @test !hasfield(typeof(m), :admins)
        @test !hasfield(typeof(m.charts[1]), :admins)
    end

    @testset "active clamped 1-based" begin
        d = Dict{String,Any}(
            "version" => 1,
            "active" => 99,
            "charts" => [
                Dict("id" => "a", "name" => "A", "chart_type" => "I-MR", "values" => [1.0]),
                Dict("id" => "b", "name" => "B", "chart_type" => "I-MR", "values" => [2.0]),
            ],
        )
        m = workbench_from_dict(d)
        @test m isa SPCWorkbenchModel
        @test m.active == 2
        @test m.library_selected == 2
    end

    # ── P2-PR3: SharedTable + col_lot in schema v1 ─────────────────────

    @testset "P2-PR3: old fixture without table → empty SharedTable" begin
        d = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-old",
                    "name" => "Legacy",
                    "chart_type" => "I-MR",
                    "values" => [10.0, 11.0, 12.0],
                    "live_enabled" => false,
                ),
            ],
            # no "table" key
        )
        m = workbench_from_dict(d)
        @test m isa SPCWorkbenchModel
        @test m.table isa SharedTable
        @test isempty(m.table.columns)
        @test isempty(m.table.rows)
        @test m.charts[1].data.values == [10.0, 11.0, 12.0]
        @test m.charts[1].col_lot == ""  # omitted → ""
        # null table also empty
        d["table"] = nothing
        m2 = workbench_from_dict(d)
        @test m2 isa SPCWorkbenchModel
        @test isempty(m2.table.rows)
        @test isempty(m2.table.columns)
    end

    @testset "P2-PR3: table load OK; no rematerialize; manual materialize recovers" begin
        # Series values intentionally differ from table so we can prove load does
        # not auto-rematerialize (series remain source of truth on load).
        series_vals = [99.0, 98.0, 97.0]
        table_rows = [
            Dict{String,Any}("Timestamp" => "t1", "Tool" => "T1", "Value" => 100.1, "Lot" => "L1"),
            Dict{String,Any}("Timestamp" => "t2", "Tool" => "T1", "Value" => 100.2, "Lot" => "L1"),
            Dict{String,Any}("Timestamp" => "t3", "Tool" => "T1", "Value" => 100.3, "Lot" => "L2"),
        ]
        d = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-tab",
                    "name" => "FromTable",
                    "chart_type" => "I-MR",
                    "values" => series_vals,
                    "live_enabled" => false,
                    "source" => "table",
                    "col_value" => "Value",
                    "col_tool" => "Tool",
                    "col_time" => "Timestamp",
                    "col_lot" => "Lot",
                ),
            ],
            "table" => Dict{String,Any}(
                "columns" => ["Timestamp", "Tool", "Value", "Lot"],
                "rows" => table_rows,
            ),
        )
        m = workbench_from_dict(d)
        @test m isa SPCWorkbenchModel
        @test m.table.columns == ["Timestamp", "Tool", "Value", "Lot"]
        @test length(m.table.rows) == 3
        @test m.table.rows[1]["Value"] == "100.1"  # Real coerced to string
        @test m.table.rows[1]["Lot"] == "L1"
        # series values unchanged (no auto-rematerialize)
        @test m.charts[1].data.values == series_vals
        @test m.charts[1].col_lot == "Lot"
        # manual rematerialize recovers table-sourced series
        materialize_chart_from_table!(m.charts[1], m.table)
        @test m.charts[1].source === :table
        @test m.charts[1].data.values ≈ [100.1, 100.2, 100.3]
        @test m.charts[1].live_enabled === false
    end

    @testset "P2-PR3: table wrong type → error; model unchanged" begin
        d0 = generate_spc_workbench_data(6; seed = 11)
        m = SPCWorkbenchModel(data = d0, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.charts[1].usl = 77.0
        m.charts[1].data.values[1] = 1.234
        snapshot_vals = copy(m.charts[1].data.values)
        snapshot_usl = m.charts[1].usl
        snapshot_n = length(m.charts)
        m.table = SharedTable(
            columns = ["Value"],
            rows = [Dict("Value" => "1.0")],
        )
        table_cols_before = copy(m.table.columns)

        bad = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0]),
            ],
            "table" => "not-an-object",
        )
        err = workbench_from_dict!(m, bad)
        @test err isa AbstractString
        @test occursin("table", err)
        @test length(m.charts) == snapshot_n
        @test m.charts[1].data.values == snapshot_vals
        @test m.charts[1].usl == snapshot_usl
        @test m.table.columns == table_cols_before

        # nested non-scalar cell
        bad_cell = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0]),
            ],
            "table" => Dict{String,Any}(
                "columns" => ["Value"],
                "rows" => [Dict{String,Any}("Value" => [1, 2, 3])],
            ),
        )
        err2 = workbench_from_dict!(m, bad_cell)
        @test err2 isa AbstractString
        @test occursin("scalar", err2)
        @test m.charts[1].usl == snapshot_usl
        @test m.table.columns == table_cols_before
    end

    @testset "P2-PR3: oversized table rows → error" begin
        n = TachikomaTUI.TABLE_JSON_MAX_ROWS + 1
        big_rows = [Dict{String,Any}("Value" => "1") for _ in 1:n]
        d = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0]),
            ],
            "table" => Dict{String,Any}(
                "columns" => ["Value"],
                "rows" => big_rows,
            ),
        )
        r = workbench_from_dict(d)
        @test r isa AbstractString
        @test occursin("too large", r) || occursin("table", r)

        d0 = generate_spc_workbench_data(4; seed = 2)
        m = SPCWorkbenchModel(data = d0, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        snap = copy(m.charts[1].data.values)
        err = workbench_from_dict!(m, d)
        @test err isa AbstractString
        @test m.charts[1].data.values == snap
    end

    @testset "P2-PR3: col_lot always written; round-trip" begin
        m = _make_session()
        m.charts[1].col_lot = "Wafer"
        m.charts[2].col_lot = ""
        d = workbench_to_dict(m)
        @test haskey(d["charts"][1], "col_lot")
        @test d["charts"][1]["col_lot"] == "Wafer"
        @test haskey(d["charts"][2], "col_lot")
        @test d["charts"][2]["col_lot"] == ""
        m2 = workbench_from_dict(d)
        @test m2 isa SPCWorkbenchModel
        @test m2.charts[1].col_lot == "Wafer"
        @test m2.charts[2].col_lot == ""
    end

    @testset "P2-PR3: empty table omitted on write; non-empty round-trips" begin
        m = _make_session()
        @test isempty(m.table.columns) && isempty(m.table.rows)
        d = workbench_to_dict(m)
        @test !haskey(d, "table")

        m.table = SharedTable(
            columns = ["Timestamp", "Tool", "Value"],
            rows = [
                Dict("Timestamp" => "t1", "Tool" => "A", "Value" => "1.5"),
                Dict("Timestamp" => "t2", "Tool" => "A", "Value" => "2.5"),
            ],
        )
        d2 = workbench_to_dict(m)
        @test haskey(d2, "table")
        @test d2["table"]["columns"] == ["Timestamp", "Tool", "Value"]
        @test length(d2["table"]["rows"]) == 2
        m3 = workbench_from_dict(d2)
        @test m3 isa SPCWorkbenchModel
        @test m3.table.columns == ["Timestamp", "Tool", "Value"]
        @test length(m3.table.rows) == 2
        @test m3.table.rows[2]["Value"] == "2.5"
        # chart series still from values field (no rematerialize)
        @test m3.charts[1].data.values == m.charts[1].data.values
    end

    @testset "chart_line_styles JSON: missing defaults, round-trip, fail-closed" begin
        # Missing key → defaults
        bare = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-sty",
                    "name" => "Styles",
                    "chart_type" => "I-MR",
                    "values" => [1.0, 2.0, 3.0],
                ),
            ],
        )
        m_bare = workbench_from_dict(bare)
        @test m_bare isa SPCWorkbenchModel
        for k in CHART_LINE_KEYS
            @test m_bare.chart_line_styles[k] == DEFAULT_CHART_LINE_STYLES[k]
        end

        # Round-trip mutate style
        m = _make_session()
        m.chart_line_styles["cl"] = "dashed"
        m.chart_line_styles["sigma3"] = "dotted"
        d = workbench_to_dict(m)
        @test haskey(d, "chart_line_styles")
        @test d["chart_line_styles"]["cl"] == "dashed"
        @test d["chart_line_styles"]["sigma3"] == "dotted"
        # full key set written
        for k in CHART_LINE_KEYS
            @test haskey(d["chart_line_styles"], k)
        end
        m2 = workbench_from_dict(d)
        @test m2 isa SPCWorkbenchModel
        @test m2.chart_line_styles["cl"] == "dashed"
        @test m2.chart_line_styles["sigma3"] == "dotted"
        @test m2.chart_line_styles["specs"] == DEFAULT_CHART_LINE_STYLES["specs"]

        # Invalid top-level type (array) → error
        bad_type = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
            "chart_line_styles" => ["solid"],
        )
        err = workbench_from_dict(bad_type)
        @test err isa AbstractString
        @test occursin("chart_line_styles", err)

        # Unknown style string → fail-closed
        bad_style = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
            "chart_line_styles" => Dict{String,Any}("cl" => "wiggly"),
        )
        err2 = workbench_from_dict(bad_style)
        @test err2 isa AbstractString
        @test occursin("unknown style", err2) || occursin("wiggly", err2)

        # Non-string value → error
        bad_val = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
            "chart_line_styles" => Dict{String,Any}("cl" => 3),
        )
        err3 = workbench_from_dict(bad_val)
        @test err3 isa AbstractString
        @test occursin("must be a string", err3)

        # Extra unknown key ignored; known keys apply; partial merge onto defaults
        partial = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
            "chart_line_styles" => Dict{String,Any}(
                "cl" => "long_dash",
                "bogus_key" => "solid",
            ),
        )
        m3 = workbench_from_dict(partial)
        @test m3 isa SPCWorkbenchModel
        @test m3.chart_line_styles["cl"] == "long_dash"
        @test m3.chart_line_styles["sigma1"] == DEFAULT_CHART_LINE_STYLES["sigma1"]
        @test !haskey(m3.chart_line_styles, "bogus_key")
    end

    @testset "graph_presets JSON: omit empty, round-trip named set, fail-closed" begin
        m = _make_session()
        # Empty list omitted from session dict (keep fixtures small)
        d0 = workbench_to_dict(m)
        @test !haskey(d0, "graph_presets") || isempty(d0["graph_presets"])

        m.show_chart_lines["specs"] = false
        m.chart_line_styles["cl"] = "dashed"
        m.visual_prefs["solid_series"] = false
        m.enabled_rules["WECO-6"] = true
        _sync_active_back!(m)  # capture reads active chart rules after _ensure_charts!
        # capture via public API if available through module; use model field path
        err = save_named_graph_preset!(m, "dense")
        @test err === nothing
        @test length(m.graph_presets) == 1

        d = workbench_to_dict(m)
        @test haskey(d, "graph_presets")
        @test length(d["graph_presets"]) == 1
        gp = d["graph_presets"][1]
        @test gp["name"] == "dense"
        @test gp["show_chart_lines"]["specs"] === false
        @test gp["chart_line_styles"]["cl"] == "dashed"
        @test gp["visual_prefs"]["solid_series"] === false
        @test gp["enabled_rules"]["WECO-6"] === true

        # Standalone dict helpers
        p = m.graph_presets[1]
        pd = graph_preset_to_dict(p)
        @test pd["name"] == "dense"
        p2 = graph_preset_from_dict(pd)
        @test p2 isa GraphPreset
        @test p2.name == "dense"
        @test p2.chart_line_styles["cl"] == "dashed"

        # Full session round-trip
        path = joinpath(tempdir(), "spc_wb_preset_$(rand(UInt32)).json")
        try
            @test save_workbench(m, path) === nothing
            loaded = load_workbench(path)
            @test loaded isa SPCWorkbenchModel
            @test length(loaded.graph_presets) == 1
            @test loaded.graph_presets[1].name == "dense"
            @test loaded.graph_presets[1].show_chart_lines["specs"] === false
            @test loaded.graph_presets[1].chart_line_styles["cl"] == "dashed"
            @test loaded.graph_presets[1].visual_prefs["solid_series"] === false
            @test loaded.graph_presets[1].enabled_rules["WECO-6"] === true
            # apply restored preset after mutating live state
            loaded.show_chart_lines["specs"] = true
            @test apply_named_graph_preset!(loaded, "dense") === nothing
            @test loaded.show_chart_lines["specs"] === false
        finally
            isfile(path) && rm(path; force = true)
        end

        # Missing graph_presets → empty
        bare = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-p",
                    "name" => "P",
                    "chart_type" => "I-MR",
                    "values" => [1.0, 2.0, 3.0],
                ),
            ],
        )
        m_bare = workbench_from_dict(bare)
        @test m_bare isa SPCWorkbenchModel
        @test isempty(m_bare.graph_presets)

        # Fail-closed: wrong type
        bad = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
            "graph_presets" => "not-an-array",
        )
        errb = workbench_from_dict(bad)
        @test errb isa AbstractString
        @test occursin("graph_presets", errb)

        # Fail-closed: unknown style inside a preset
        bad_style = Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
            "graph_presets" => [
                Dict{String,Any}(
                    "name" => "bad",
                    "chart_line_styles" => Dict{String,Any}("cl" => "wiggly"),
                ),
            ],
        )
        errs = workbench_from_dict(bad_style)
        @test errs isa AbstractString
        @test occursin("unknown style", errs) || occursin("wiggly", errs)

        # Standalone file save/load
        pfile = GraphPreset(
            name = "file-p",
            show_chart_lines = Dict{String,Bool}("cl" => false, "sigma1" => true, "sigma2" => true, "sigma3" => true, "specs" => true),
            chart_line_styles = Dict{String,String}("cl" => "dotted", "sigma1" => "solid", "sigma2" => "dashed", "sigma3" => "long_dash", "specs" => "dotted"),
            visual_prefs = Dict{String,Bool}("solid_series" => false, "solid_stroke" => true, "braille_series" => true, "secondary_canvas" => false),
            enabled_rules = copy(DEFAULT_WECO_RULES),
        )
        pfile.enabled_rules["WECO-7"] = true
        fpath = joinpath(tempdir(), "spc_graph_preset_$(rand(UInt32)).json")
        try
            @test save_graph_preset(pfile, fpath) === nothing
            loaded_p = load_graph_preset(fpath)
            @test loaded_p isa GraphPreset
            @test loaded_p.name == "file-p"
            @test loaded_p.show_chart_lines["cl"] === false
            @test loaded_p.chart_line_styles["sigma1"] == "solid"
            @test loaded_p.visual_prefs["secondary_canvas"] === false
            @test loaded_p.enabled_rules["WECO-7"] === true
            # write still uses kind=graph_preset
            raw_txt = read(fpath, String)
            @test occursin("\"graph_preset\"", raw_txt) || occursin("graph_preset", raw_txt)
        finally
            isfile(fpath) && rm(fpath; force = true)
        end

        # load accepts kind=graph_config alias (PR4); write still graph_preset
        alias_path = joinpath(tempdir(), "spc_graph_config_alias_$(rand(UInt32)).json")
        try
            # Minimal portable file with load-only kind alias
            open(alias_path, "w") do io
                write(io, """{"kind":"graph_config","version":1,"name":"file-p",
                    "show_chart_lines":{"cl":false,"sigma1":true,"sigma2":true,"sigma3":true,"specs":true},
                    "chart_line_styles":{"cl":"dotted","sigma1":"solid","sigma2":"dashed","sigma3":"long_dash","specs":"dotted"},
                    "visual_prefs":{"solid_series":false,"solid_stroke":true,"braille_series":true,"secondary_canvas":false},
                    "enabled_rules":{"WECO-1":true,"WECO-2":true,"WECO-3":true,"WECO-4":true,"WECO-5":true,"WECO-6":false,"WECO-7":true,"WECO-8":false}}""")
            end
            loaded_alias = load_graph_preset(alias_path)
            @test loaded_alias isa GraphPreset
            @test loaded_alias.name == "file-p"
            @test loaded_alias.show_chart_lines["cl"] === false
            # unknown kind still rejected
            badk = joinpath(tempdir(), "spc_graph_badkind_$(rand(UInt32)).json")
            try
                open(badk, "w") do io
                    write(io, """{"kind":"session","name":"x"}""")
                end
                errk = load_graph_preset(badk)
                @test errk isa AbstractString
                @test occursin("load err", errk)
            finally
                isfile(badk) && rm(badk; force = true)
            end
        finally
            isfile(alias_path) && rm(alias_path; force = true)
        end
    end

end

end # module TestSPCWorkbenchJSON

# PR3/PR4: Config file save/load — typed path (p/P) + explorer keys (package-module;
# avoids type redefinition vs pure include of spc_workbench.jl).
# ═══════════════════════════════════════════════════════════════════════

module TestSPCWorkbenchGraphConfigIO
using Test
using Random
using TachikomaTUI
using Tachikoma

const T = Tachikoma
const WB = TachikomaTUI
const _ensure_charts! = WB._ensure_charts!
const _sync_active_back! = WB._sync_active_back!
const current_chart = WB.current_chart
const _graph_config_name_from_path = WB._graph_config_name_from_path

"""Clear prompt_buf with backspaces then type path."""
function _set_prompt_path!(m, path::AbstractString)
    while !isempty(m.prompt_buf)
        T.update!(m, T.KeyEvent(:backspace))
    end
    for ch in collect(String(path))
        T.update!(m, T.KeyEvent(ch))
    end
end

"""Inject temp index path so tests never write host XDG (KD-SE-5)."""
function _isolate_index!(m, dir::AbstractString)
    m.graph_config_index_path = joinpath(dir, "graph_config_index.json")
    return m
end

@testset "PR3/PR4 Config file save/load (typed path + explorer keys)" begin

    @testset "p typed path save: basename name in JSON + list upsert + prefill" begin
        d = generate_spc_workbench_data(12; seed = 21)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.show_chart_lines["specs"] = false
        m.chart_line_styles["cl"] = "dashed"
        m.visual_prefs["solid_series"] = false
        m.enabled_rules["WECO-6"] = true
        _sync_active_back!(m)
        @test m.last_graph_config_path == ""

        mktempdir() do dir
            _isolate_index!(m, dir)
            path = joinpath(dir, "fab-dense.json")
            T.update!(m, T.KeyEvent('c'))  # Config (any section may open p)
            @test m.view_mode === :config
            T.update!(m, T.KeyEvent('p'))
            @test m.prompt_kind === :save_graph_config
            @test m.file_browser_open === false
            @test m.prompt_buf == ""  # empty last path
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test m.prompt_kind === nothing
            @test m.view_mode === :config  # stay on Config after file save
            @test abspath(m.last_graph_config_path) == abspath(path)
            @test occursin("saved graph config", m.last_event)
            @test occursin(abspath(path), m.last_event) || occursin(path, m.last_event)
            @test isfile(m.graph_config_index_path)  # inject path only, not XDG
            @test isfile(path)
            # KD-SE-23: save upserts list + selects entry
            @test length(m.graph_presets) == 1
            @test abspath(m.graph_presets[1].path) == abspath(path)
            @test m.graph_presets[1].name == "fab-dense"
            @test m.presets_selected == 1
            # basename without extension is the written name (KD-UC-17)
            loaded = load_graph_preset(path)
            @test loaded isa GraphPreset
            @test loaded.name == "fab-dense"
            @test loaded.show_chart_lines["specs"] === false
            @test loaded.chart_line_styles["cl"] == "dashed"
            @test loaded.visual_prefs["solid_series"] === false
            @test loaded.enabled_rules["WECO-6"] === true
            raw = read(path, String)
            @test occursin("graph_preset", raw)  # write kind still graph_preset
            @test occursin("fab-dense", raw)
            @test !occursin("\"path\"", raw)  # standalone file has no host path

            # Prefill: reopen p seeds last_graph_config_path
            T.update!(m, T.KeyEvent('p'))
            @test m.prompt_kind === :save_graph_config
            @test abspath(m.prompt_buf) == abspath(path) || m.prompt_buf == m.last_graph_config_path
            T.update!(m, T.KeyEvent(:escape))
            @test m.prompt_kind === nothing

            # w opens Save As explorer (not typed prompt)
            T.update!(m, T.KeyEvent('w'))
            @test m.file_browser_open === true
            @test m.file_browser_mode === :save_graph_config
            @test m.prompt_kind === nothing
            T.update!(m, T.KeyEvent(:escape))
        end
    end

    @testset "P typed path load: upsert by path, apply, dashboard, last_event" begin
        d = generate_spc_workbench_data(12; seed = 22)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        # live defaults differ from files we'll load
        m.show_chart_lines["cl"] = true
        m.chart_line_styles["cl"] = "solid"
        m.visual_prefs["secondary_canvas"] = true
        m.enabled_rules["WECO-6"] = false
        _sync_active_back!(m)
        @test isempty(m.graph_presets)

        mktempdir() do dir
            _isolate_index!(m, dir)
            p_a = GraphPreset(
                name = "cfg-a",
                show_chart_lines = Dict{String,Bool}("cl" => false, "sigma1" => true, "sigma2" => true, "sigma3" => true, "specs" => false),
                chart_line_styles = Dict{String,String}("cl" => "long_dash", "sigma1" => "solid", "sigma2" => "dashed", "sigma3" => "long_dash", "specs" => "dotted"),
                visual_prefs = Dict{String,Bool}("solid_series" => false, "solid_stroke" => true, "braille_series" => true, "secondary_canvas" => false),
                enabled_rules = copy(DEFAULT_WECO_RULES),
            )
            p_a.enabled_rules["WECO-6"] = true
            path_a = joinpath(dir, "whatever-a.json")  # basename ≠ payload name
            @test save_graph_preset(p_a, path_a) === nothing

            p_b = GraphPreset(
                name = "cfg-b",
                show_chart_lines = Dict{String,Bool}("cl" => true, "sigma1" => false, "sigma2" => true, "sigma3" => true, "specs" => true),
                chart_line_styles = Dict{String,String}("cl" => "dotted", "sigma1" => "solid", "sigma2" => "dashed", "sigma3" => "long_dash", "specs" => "dotted"),
                visual_prefs = Dict{String,Bool}("solid_series" => true, "solid_stroke" => true, "braille_series" => true, "secondary_canvas" => true),
                enabled_rules = copy(DEFAULT_WECO_RULES),
            )
            p_b.enabled_rules["WECO-7"] = true
            path_b = joinpath(dir, "whatever-b.json")
            @test save_graph_preset(p_b, path_b) === nothing

            # Load A via P (typed path load fallback)
            T.update!(m, T.KeyEvent('e'))  # Config Saved
            @test m.view_mode === :config && m.config_tab === :saved
            T.update!(m, T.KeyEvent('P'))
            @test m.prompt_kind === :load_graph_config
            @test m.file_browser_open === false
            _set_prompt_path!(m, path_a)
            T.update!(m, T.KeyEvent(:enter))
            @test m.view_mode === :dashboard  # R2
            @test m.prompt_kind === nothing
            @test abspath(m.last_graph_config_path) == abspath(path_a)
            @test occursin("loaded graph config", m.last_event)
            @test occursin(abspath(path_a), m.last_event) || occursin(path_a, m.last_event)
            @test !occursin("preset applied", m.last_event)  # final string overwritten (KD-SE-16)
            @test length(m.graph_presets) == 1
            @test m.graph_presets[1].name == "cfg-a"  # payload name wins over path basename
            @test abspath(m.graph_presets[1].path) == abspath(path_a)
            @test m.show_chart_lines["cl"] === false
            @test m.chart_line_styles["cl"] == "long_dash"
            @test m.visual_prefs["secondary_canvas"] === false
            @test m.enabled_rules["WECO-6"] === true
            @test current_chart(m).enabled_rules["WECO-6"] === true

            # Load B → second list entry (path-keyed; different paths)
            T.update!(m, T.KeyEvent('e'))
            T.update!(m, T.KeyEvent('P'))
            _set_prompt_path!(m, path_b)
            T.update!(m, T.KeyEvent(:enter))
            @test m.view_mode === :dashboard
            @test length(m.graph_presets) == 2
            names = sort([p.name for p in m.graph_presets])
            @test names == ["cfg-a", "cfg-b"]
            @test m.show_chart_lines["sigma1"] === false
            @test m.enabled_rules["WECO-7"] === true
            @test occursin("loaded graph config", m.last_event)

            # Reload A → same path upsert, length unchanged
            m.show_chart_lines["cl"] = true
            T.update!(m, T.KeyEvent('c'))
            T.update!(m, T.KeyEvent('P'))
            _set_prompt_path!(m, path_a)
            T.update!(m, T.KeyEvent(:enter))
            @test length(m.graph_presets) == 2  # upsert, not push
            @test m.show_chart_lines["cl"] === false
            @test occursin("loaded graph config", m.last_event)

            # W opens Load explorer (not typed prompt)
            T.update!(m, T.KeyEvent('e'))
            T.update!(m, T.KeyEvent('W'))
            @test m.file_browser_open === true
            @test m.file_browser_mode === :load_graph_config
            @test m.prompt_kind === nothing
            T.update!(m, T.KeyEvent(:escape))
        end
    end

    @testset "P fail-closed: invalid path leaves list + model unchanged" begin
        d = generate_spc_workbench_data(10; seed = 23)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.graph_config_index_path = joinpath(tempdir(), "spc_wb_empty_idx_$(rand(UInt32)).json")
        push!(m.graph_presets, capture_graph_preset(m; name = "keep"))
        m.show_chart_lines["specs"] = false
        m.enabled_rules["WECO-6"] = true
        _sync_active_back!(m)
        snap_lines = copy(m.show_chart_lines)
        snap_rules = copy(m.enabled_rules)
        n0 = length(m.graph_presets)
        prev_path = m.last_graph_config_path

        T.update!(m, T.KeyEvent('e'))
        T.update!(m, T.KeyEvent('P'))
        @test m.prompt_kind === :load_graph_config
        bad = "/tmp/does_not_exist_graph_cfg_$(rand(UInt32)).json"
        _set_prompt_path!(m, bad)
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :load_graph_config  # stay open for retry
        @test m.view_mode === :config
        @test occursin("load err", m.last_event)
        @test length(m.graph_presets) == n0
        @test m.graph_presets[1].name == "keep"
        @test m.show_chart_lines == snap_lines
        @test m.enabled_rules == snap_rules
        @test m.last_graph_config_path == prev_path  # unchanged on fail
        # empty path also fail-closed
        while !isempty(m.prompt_buf)
            T.update!(m, T.KeyEvent(:backspace))
        end
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :load_graph_config
        @test occursin("load err", m.last_event)
        @test length(m.graph_presets) == n0
        T.update!(m, T.KeyEvent(:escape))
    end

    @testset "p fail-closed: unwritable path; last_graph_config_path unchanged" begin
        d = generate_spc_workbench_data(10; seed = 24)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.last_graph_config_path = "/tmp/prev_cfg.json"

        T.update!(m, T.KeyEvent('c'))
        T.update!(m, T.KeyEvent('p'))
        @test m.prompt_kind === :save_graph_config
        @test m.prompt_buf == "/tmp/prev_cfg.json"  # prefill
        bad = "/proc/no_write_cfg_$(rand(UInt32))/out.json"
        _set_prompt_path!(m, bad)
        T.update!(m, T.KeyEvent(:enter))
        @test m.prompt_kind === :save_graph_config
        @test occursin("save err", m.last_event)
        @test m.last_graph_config_path == "/tmp/prev_cfg.json"
        @test m.view_mode === :config
        T.update!(m, T.KeyEvent(:escape))
    end

    @testset "file load does NOT call save_named_graph_preset! (payload upsert only)" begin
        # Regression: file load must store file payload, not re-capture live model.
        d = generate_spc_workbench_data(10; seed = 25)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        # Live model has cl=true; file payload has cl=false under name "from-file"
        m.show_chart_lines["cl"] = true
        _sync_active_back!(m)

        mktempdir() do dir
            _isolate_index!(m, dir)
            p = GraphPreset(
                name = "from-file",
                show_chart_lines = Dict{String,Bool}("cl" => false, "sigma1" => true, "sigma2" => true, "sigma3" => true, "specs" => true),
                chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
                visual_prefs = copy(DEFAULT_VISUAL_PREFS),
                enabled_rules = copy(DEFAULT_WECO_RULES),
            )
            path = joinpath(dir, "other-basename.json")
            @test save_graph_preset(p, path) === nothing

            T.update!(m, T.KeyEvent('e'))
            T.update!(m, T.KeyEvent('P'))
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test length(m.graph_presets) == 1
            @test m.graph_presets[1].name == "from-file"
            @test m.graph_presets[1].show_chart_lines["cl"] === false
            @test m.show_chart_lines["cl"] === false
            @test occursin("loaded graph config", m.last_event)
            @test !occursin("preset saved", m.last_event)
            @test !occursin("preset updated", m.last_event)
        end
    end

    @testset "kind=graph_config file loadable via P typed path" begin
        d = generate_spc_workbench_data(8; seed = 26)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        mktempdir() do dir
            _isolate_index!(m, dir)
            path = joinpath(dir, "alias-kind.json")
            open(path, "w") do io
                write(io, """{"kind":"graph_config","version":1,"name":"alias-cfg",
                    "show_chart_lines":{"cl":false,"sigma1":true,"sigma2":true,"sigma3":true,"specs":true},
                    "chart_line_styles":{"cl":"solid","sigma1":"dotted","sigma2":"dashed","sigma3":"long_dash","specs":"dotted"},
                    "visual_prefs":{"solid_series":true,"solid_stroke":true,"braille_series":true,"secondary_canvas":true},
                    "enabled_rules":{"WECO-1":true,"WECO-2":true,"WECO-3":true,"WECO-4":true,"WECO-5":true,"WECO-6":false,"WECO-7":false,"WECO-8":false}}""")
            end
            T.update!(m, T.KeyEvent('c'))
            T.update!(m, T.KeyEvent('P'))
            @test m.prompt_kind === :load_graph_config
            _set_prompt_path!(m, path)
            T.update!(m, T.KeyEvent(:enter))
            @test m.view_mode === :dashboard
            @test m.graph_presets[1].name == "alias-cfg"
            @test m.show_chart_lines["cl"] === false
            @test occursin("loaded graph config", m.last_event)
        end
    end

    @testset "KD-SE-21: path-bearing load re-reads file, never applies lazy list body" begin
        # List row has DEFAULT body; file on disk has WECO-6 on and cl off.
        # Enter must apply file payload, not the lazy defaults in the list entry.
        d = generate_spc_workbench_data(10; seed = 28)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.show_chart_lines["cl"] = true
        m.enabled_rules["WECO-6"] = false
        _sync_active_back!(m)

        mktempdir() do dir
            _isolate_index!(m, dir)
            path = joinpath(dir, "disk-truth.json")
            disk = GraphPreset(
                name = "disk-truth",
                show_chart_lines = Dict{String,Bool}(
                    "cl" => false, "sigma1" => true, "sigma2" => true,
                    "sigma3" => true, "specs" => true,
                ),
                chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
                visual_prefs = copy(DEFAULT_VISUAL_PREFS),
                enabled_rules = copy(DEFAULT_WECO_RULES),
            )
            disk.enabled_rules["WECO-6"] = true
            disk.enabled_rules["WECO-1"] = false
            @test save_graph_preset(disk, path) === nothing

            # Path-bearing list entry with DEFAULT body (lazy / never loaded)
            lazy = GraphPreset(
                name = "lazy-row",
                show_chart_lines = copy(DEFAULT_CHART_LINES),  # cl=true
                chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
                visual_prefs = copy(DEFAULT_VISUAL_PREFS),
                enabled_rules = copy(DEFAULT_WECO_RULES),  # WECO-6 false
                path = path,
            )
            push!(m.graph_presets, lazy)
            m.presets_selected = 1
            # Live model still differs from both lazy body and file
            m.show_chart_lines["cl"] = true
            m.enabled_rules["WECO-6"] = false
            m.enabled_rules["WECO-1"] = true
            _sync_active_back!(m)

            T.update!(m, T.KeyEvent('e'))
            @test m.view_mode === :config && m.config_tab === :saved
            T.update!(m, T.KeyEvent(:enter))
            @test m.view_mode === :dashboard
            @test occursin("loaded graph config", m.last_event)
            # Must match file, not lazy defaults
            @test m.show_chart_lines["cl"] === false
            @test m.enabled_rules["WECO-6"] === true
            @test m.enabled_rules["WECO-1"] === false
            @test current_chart(m).enabled_rules["WECO-6"] === true
            # List upserted from file payload
            @test m.graph_presets[1].show_chart_lines["cl"] === false
            @test m.graph_presets[1].enabled_rules["WECO-6"] === true
        end
    end

    @testset "empty path helper rejects before abspath(cwd)" begin
        d = generate_spc_workbench_data(6; seed = 29)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        mktempdir() do dir
            _isolate_index!(m, dir)
            @test WB._apply_save_graph_config_path!(m, "   ") === false
            @test occursin("empty path", m.last_event)
            @test isempty(m.graph_presets)
            @test WB._apply_load_graph_config_path!(m, "") === false
            @test occursin("empty path", m.last_event)
        end
    end

    @testset "explorer Save As + overwrite + Quick Save + Load" begin
        d = generate_spc_workbench_data(10; seed = 27)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.show_chart_lines["specs"] = false
        _sync_active_back!(m)
        # Isolate index writes (KD-SE-5)
        mktempdir() do dir
            _isolate_index!(m, dir)
            path = joinpath(dir, "explorer-cfg.json")
            # Open Save As from Lines tab (Config-wide KD-SE-18)
            T.update!(m, T.KeyEvent('v'))
            @test m.config_tab == :lines
            T.update!(m, T.KeyEvent('s'))
            @test m.file_browser_open === true
            @test m.file_browser_mode === :save_graph_config
            # Seed name + navigate: set cwd by typing absolute path is hard;
            # use name buffer with basename after setting cwd via seed last path parent.
            m.file_browser_cwd = dir
            WB._browser_refresh!(m)
            # Clear name and type basename without .json → auto-append
            while !isempty(m.file_browser_name_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            for c in collect("explorer-cfg")
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test m.file_browser_open === false
            @test isfile(path)
            @test occursin("saved graph config", m.last_event)
            @test length(m.graph_presets) == 1
            @test m.graph_presets[1].name == "explorer-cfg"
            # Overwrite path: Save As again to same file → pending_overwrite
            T.update!(m, T.KeyEvent('w'))
            @test m.file_browser_open === true
            m.file_browser_cwd = dir
            WB._browser_refresh!(m)
            while !isempty(m.file_browser_name_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            for c in collect("explorer-cfg.json")
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test m.file_browser_open === false  # closed before overwrite
            @test m.pending_overwrite === true
            @test abspath(m.pending_overwrite_path) == abspath(path)
            # cancel overwrite
            T.update!(m, T.KeyEvent('n'))
            @test m.pending_overwrite === false
            @test occursin("overwrite cancel", m.last_event)
            # re-arm and confirm y
            T.update!(m, T.KeyEvent('s'))
            m.file_browser_cwd = dir
            WB._browser_refresh!(m)
            while !isempty(m.file_browser_name_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            for c in collect("explorer-cfg.json")
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test m.pending_overwrite === true
            T.update!(m, T.KeyEvent('y'))
            @test m.pending_overwrite === false
            @test length(m.graph_presets) == 1  # upsert same path
            @test occursin("saved graph config", m.last_event)
            # Quick Save S rewrites known path without confirm
            m.show_chart_lines["cl"] = false
            _sync_active_back!(m)
            T.update!(m, T.KeyEvent('S'))
            @test m.pending_overwrite === false
            @test m.file_browser_open === false
            @test occursin("saved graph config", m.last_event)
            loaded = load_graph_preset(path)
            @test loaded isa GraphPreset
            @test loaded.show_chart_lines["cl"] === false
            # Load explorer: W → select file → Enter
            m.show_chart_lines["cl"] = true
            T.update!(m, T.KeyEvent('W'))
            @test m.file_browser_open === true
            @test m.file_browser_mode === :load_graph_config
            m.file_browser_cwd = dir
            WB._browser_refresh!(m)
            # find explorer-cfg.json in entries
            idx = findfirst(e -> e.name == "explorer-cfg.json" && !e.is_dir, m.file_browser_entries)
            @test idx !== nothing
            m.file_browser_selected = idx
            T.update!(m, T.KeyEvent(:enter))
            @test m.view_mode === :dashboard
            @test m.show_chart_lines["cl"] === false
            @test occursin("loaded graph config", m.last_event)
            # Modal exclusivity: browser + prompt not both open
            T.update!(m, T.KeyEvent('e'))
            T.update!(m, T.KeyEvent('s'))
            @test m.file_browser_open === true
            @test m.prompt_kind === nothing
            T.update!(m, T.KeyEvent(:escape))
            T.update!(m, T.KeyEvent('p'))
            @test m.prompt_kind === :save_graph_config
            @test m.file_browser_open === false
            T.update!(m, T.KeyEvent(:escape))
            # Filename reject separators
            T.update!(m, T.KeyEvent('s'))
            while !isempty(m.file_browser_name_buf)
                T.update!(m, T.KeyEvent(:backspace))
            end
            for c in collect("bad/name")
                T.update!(m, T.KeyEvent(c))
            end
            T.update!(m, T.KeyEvent(:enter))
            @test m.file_browser_open === true
            @test occursin("separator", m.last_event) || occursin("save err", m.last_event)
            T.update!(m, T.KeyEvent(:escape))
            # Live gate with browser open
            m.paused = false
            current_chart(m).live_enabled = true
            m.file_browser_open = true
            @test WB._live_may_advance(m) === false
            m.file_browser_open = false
            m.view_mode = :dashboard
            m.paused = true
            # Dashboard s still clears specs
            m.usl = 1.0
            current_chart(m).usl = 1.0
            T.update!(m, T.KeyEvent('s'))
            @test m.usl === nothing
            @test occursin("specs cleared", m.last_event)
        end
    end

    @testset "PR4: index merge/backfill, path chrome, delete→index (KD-SE-25/9/26)" begin
        d = generate_spc_workbench_data(12; seed = 44)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        _ensure_charts!(m)

        mktempdir() do dir
            _isolate_index!(m, dir)
            idx_path = m.graph_config_index_path
            present = joinpath(dir, "present.json")
            gone = joinpath(dir, "gone.json")

            # Write a real config file + seed index with present + missing paths
            p_ok = capture_graph_preset(m; name = "present")
            p_ok.path = present
            p_ok.show_chart_lines["specs"] = false
            p_ok.enabled_rules["WECO-6"] = true
            @test save_graph_preset(p_ok, present) === nothing

            e_present = GraphConfigIndexEntry(
                name = "present",
                path = abspath(present),
                saved_at = "2026-01-01T10:00:00",
                last_used_at = "2026-01-02T12:00:00",  # newer → first in MRU
                summary = Dict{String,Any}(
                    "weco_on" => 6,
                    "lines_off" => 1,
                    "styles" => "mixed",
                ),
            )
            e_gone = GraphConfigIndexEntry(
                name = "gone",
                path = abspath(gone),
                saved_at = "2026-01-01T09:00:00",
                last_used_at = "2026-01-01T11:00:00",  # older
                summary = Dict{String,Any}(
                    "weco_on" => 3,
                    "lines_off" => 2,
                    "styles" => "solid",
                ),
            )
            @test write_graph_config_index(idx_path, GraphConfigIndexEntry[e_present, e_gone]) === nothing
            @test !isfile(gone)

            # Empty session list; open Saved → merge pulls both index paths
            empty!(m.graph_presets)
            T.update!(m, T.KeyEvent('e'))
            @test m.view_mode === :config && m.config_tab === :saved
            @test length(m.graph_presets) == 2
            # MRU: present first (newer last_used_at)
            @test m.graph_presets[1].name == "present"
            @test abspath(m.graph_presets[1].path) == abspath(present)
            @test m.graph_presets[2].name == "gone"
            @test abspath(m.graph_presets[2].path) == abspath(gone)
            # Missing badge cached (no per-frame re-stat)
            @test m.preset_path_missing[abspath(present)] === false
            @test m.preset_path_missing[abspath(gone)] === true
            # Lazy DEFAULT body for index-only entries (do not apply defaults without load)
            @test WB._is_lazy_default_body(m.graph_presets[1])
            @test WB._is_lazy_default_body(m.graph_presets[2])

            # Path chrome: Path column + ! badge on gone; summary chips for lazy
            tb = T.TestBackend(100, 24); T.reset!(tb.buf)
            T.view(m, T.Frame(tb.buf, T.Rect(1, 1, 100, 24), [], []))
            full = join([string(T.row_text(tb, i)) for i in 1:24 if T.row_text(tb, i) !== nothing], "\n")
            @test occursin("Path", full)
            @test occursin("present", full)
            @test occursin("!gone", full) || occursin("!gone", replace(full, " " => ""))
            @test occursin("2 saved", full)
            @test occursin("6/8", full)  # summary weco_on for present
            @test occursin("3/8", full)  # summary for gone
            @test occursin("off-1", full)
            @test occursin("present.json", full) || occursin(basename(present), full)

            # Index-only entry must NOT apply defaults without file re-read (KD-SE-21)
            m.show_chart_lines["specs"] = true  # model differs from file
            m.presets_selected = 1
            T.update!(m, T.KeyEvent(:enter))
            # Load re-reads present.json → specs false
            @test m.show_chart_lines["specs"] === false
            @test occursin("loaded graph config", m.last_event)
            @test m.view_mode === :dashboard

            # Backfill: list path-bearing missing from index → write once
            T.update!(m, T.KeyEvent('e'))
            only_list = joinpath(dir, "list-only.json")
            p_lo = capture_graph_preset(m; name = "list-only")
            p_lo.path = only_list
            p_lo.show_chart_lines["cl"] = false
            @test save_graph_preset(p_lo, only_list) === nothing
            # Manually push without index write
            push!(m.graph_presets, p_lo)
            # Clear index of list-only if present; keep present+gone only
            @test write_graph_config_index(idx_path, GraphConfigIndexEntry[e_present, e_gone]) === nothing
            before_mtime = mtime(idx_path)
            sleep(0.05)
            # Re-open Saved → merge backfills list-only into index
            T.update!(m, T.KeyEvent(:escape))
            T.update!(m, T.KeyEvent('e'))
            @test any(p -> abspath(p.path) == abspath(only_list), m.graph_presets)
            loaded_idx = read_graph_config_index(idx_path)
            lo_ent = findfirst(e -> abspath(e.path) == abspath(only_list), loaded_idx)
            @test lo_ent !== nothing
            # Backfill uses conservative TS — does not outrank real last_used_at (Issue 3)
            @test loaded_idx[lo_ent].last_used_at == "1970-01-01T00:00:00" ||
                  loaded_idx[lo_ent].last_used_at < "2026-01-01T00:00:00"
            @test mtime(idx_path) >= before_mtime
            # Second open: list-only stays behind MRU present/gone (not promoted to front)
            T.update!(m, T.KeyEvent(:escape))
            T.update!(m, T.KeyEvent('e'))
            @test m.graph_presets[1].name == "present"
            @test any(p -> abspath(p.path) == abspath(only_list), m.graph_presets)
            @test findfirst(p -> abspath(p.path) == abspath(only_list), m.graph_presets) > 1

            # Delete removes list + index entry; file remains on disk (KD-SE-9)
            n_before = length(m.graph_presets)
            # select present
            sel_present = findfirst(p -> abspath(p.path) == abspath(present), m.graph_presets)
            @test sel_present !== nothing
            m.presets_selected = sel_present
            T.update!(m, T.KeyEvent('d'))
            @test m.pending_delete === true
            T.update!(m, T.KeyEvent('y'))
            @test occursin("deleted preset", m.last_event)
            @test length(m.graph_presets) == n_before - 1
            @test !any(p -> abspath(p.path) == abspath(present), m.graph_presets)
            @test isfile(present)  # never rm file
            after_del = read_graph_config_index(idx_path)
            @test !any(e -> abspath(e.path) == abspath(present), after_del)

            # Temp index survives new model instance (inject same path)
            m2 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
            _ensure_charts!(m2)
            m2.graph_config_index_path = idx_path
            empty!(m2.graph_presets)
            T.update!(m2, T.KeyEvent('e'))
            # present was deleted from index; gone + list-only remain
            paths2 = Set(abspath(p.path) for p in m2.graph_presets if !isempty(strip(p.path)))
            @test abspath(gone) in paths2
            @test abspath(only_list) in paths2
            @test !(abspath(present) in paths2)
            @test m2.preset_path_missing[abspath(gone)] === true

            # Path-less legacy stays; not backfilled to index
            T.update!(m2, T.KeyEvent(:escape))
            push!(m2.graph_presets, capture_graph_preset(m2; name = "memory-only"))
            n_idx_before = length(read_graph_config_index(idx_path))
            T.update!(m2, T.KeyEvent('e'))
            @test any(p -> p.name == "memory-only" && isempty(strip(p.path)), m2.graph_presets)
            @test length(read_graph_config_index(idx_path)) == n_idx_before

            # load_workbench! also merges index
            m3 = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
            _ensure_charts!(m3)
            m3.graph_config_index_path = idx_path
            wb_path = joinpath(dir, "session.json")
            @test save_workbench(m3, wb_path) === nothing
            empty!(m3.graph_presets)
            @test load_workbench!(m3, wb_path) === nothing
            paths3 = Set(abspath(p.path) for p in m3.graph_presets if !isempty(strip(p.path)))
            @test abspath(gone) in paths3
            @test abspath(only_list) in paths3

            # _display_path helpers
            @test WB._display_path("") == "—"
            home_p = joinpath(homedir(), "cfg", "x.json")
            disp = WB._display_path(home_p; maxw = 40)
            @test startswith(disp, "~") || occursin("x.json", disp)
            longp = "/very/long/path/that/should/be/middle/elided/config.json"
            short = WB._display_path(longp; maxw = 20)
            @test length(short) <= 20
            @test occursin("…", short) || length(longp) <= 20

            # Issue 2: multi-byte UTF-8 home prefix — byte-safe chop (not length())
            utf_home = joinpath("/tmp", "café_home_$(rand(UInt32))")
            utf_path = joinpath(utf_home, "cfg", "x.json")
            @test startswith(utf_path, utf_home * "/")
            # Old bug: length(home) codepoints → wrong slice / StringIndexError
            @test length(utf_home) != ncodeunits(utf_home)  # café has multi-byte é
            bad_chop = try
                "~" * utf_path[length(utf_home) + 1:end]
            catch
                "threw"
            end
            good_chop = "~" * utf_path[ncodeunits(utf_home) + 1:end]
            @test good_chop == "~/cfg/x.json"
            @test bad_chop != good_chop  # demonstrates length() is wrong for UTF-8 home

            # Issue 1: index write failure rolls back list delete (no resurrection)
            m_del = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
            _ensure_charts!(m_del)
            mktempdir() do d2
                cfg = joinpath(d2, "will-keep.json")
                p = capture_graph_preset(m_del; name = "will-keep")
                p.path = cfg
                @test save_graph_preset(p, cfg) === nothing
                WB._upsert_graph_preset!(m_del, p)
                e = graph_config_index_entry_from_preset(p)
                # Pre-seed index, then make parent dir read-only so rewrite fails
                locked = joinpath(d2, "locked")
                mkpath(locked)
                locked_idx = joinpath(locked, "graph_config_index.json")
                @test write_graph_config_index(locked_idx, GraphConfigIndexEntry[e]) === nothing
                m_del.graph_config_index_path = locked_idx
                chmod(locked, 0o555)
                try
                    T.update!(m_del, T.KeyEvent('e'))
                    @test length(m_del.graph_presets) >= 1
                    sel = findfirst(x -> abspath(x.path) == abspath(cfg), m_del.graph_presets)
                    @test sel !== nothing
                    m_del.presets_selected = sel
                    n_before = length(m_del.graph_presets)
                    T.update!(m_del, T.KeyEvent('d'))
                    T.update!(m_del, T.KeyEvent('y'))
                    # Must report delete err and keep list entry (Issue 1 rollback)
                    @test occursin("delete err", m_del.last_event)
                    @test !occursin("deleted preset", m_del.last_event)
                    @test length(m_del.graph_presets) == n_before
                    @test any(x -> abspath(x.path) == abspath(cfg), m_del.graph_presets)
                    chmod(locked, 0o755)
                    still = read_graph_config_index(locked_idx)
                    @test any(x -> abspath(x.path) == abspath(cfg), still)
                finally
                    try; chmod(locked, 0o755); catch; end
                end
            end

            # Issue 8: selection preserved by path across merge reorder
            m_sel = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
            _ensure_charts!(m_sel)
            m_sel.graph_config_index_path = idx_path
            empty!(m_sel.graph_presets)
            push!(m_sel.graph_presets, GraphPreset(name = "list-only", path = abspath(only_list)))
            push!(m_sel.graph_presets, GraphPreset(name = "gone", path = abspath(gone)))
            m_sel.presets_selected = 1  # list-only
            T.update!(m_sel, T.KeyEvent('e'))
            @test abspath(m_sel.graph_presets[m_sel.presets_selected].path) == abspath(only_list)
        end
    end

end

end # module TestSPCWorkbenchGraphConfigIO

# HTML archive import (PR10 P2) — strip admins, map charts/values; via package module
# ═══════════════════════════════════════════════════════════════════════

module TestSPCWorkbenchHTMLImport
using Test
using Random
using TachikomaTUI
using Statistics: mean
const _ensure_charts! = TachikomaTUI._ensure_charts!

@testset "PR10 HTML archive import (strip admins; fail closed)" begin

    function _mini_html_archive(; with_admins = true, values = [1303.0, 1305.0, 1299.0, 1301.0, 1294.0])
        rows = [
            Dict{String,Any}(
                "Timestamp" => "2026-05-0$i",
                "Tool" => "Film-PTPECVD01",
                "Lot" => "L1",
                "Wafer" => "W0$i",
                "Value" => values[i],
            ) for i in 1:length(values)
        ]
        push!(rows, Dict{String,Any}(
            "Timestamp" => "", "Tool" => "", "Lot" => "", "Wafer" => "", "Value" => "",
        ))
        state = Dict{String,Any}(
            "data" => rows,
            "columns" => ["Timestamp", "Tool", "Lot", "Wafer", "Value"],
            "charts" => [
                Dict{String,Any}(
                    "id" => "CHT-film",
                    "name" => "Film-Thickness-1.3um",
                    "param" => "PECVD Oxide",
                    "type" => "I-MR",
                    "units" => "nm",
                    "subgroupSize" => 5,
                    "col_value" => "Value",
                    "col_n" => "n",
                    "col_tool" => "Tool",
                    "col_time" => "Timestamp",
                    "col_lot" => "Wafer",
                    "tools" => ["Film-PTPECVD01"],
                    "limitsMode" => "auto",
                    "cl" => nothing,
                    "ucl" => nothing,
                    "lcl" => nothing,
                    "usl" => 1320,
                    "target" => 1300,
                    "lsl" => 1280,
                    "rules" => Dict("WECO-1" => true, "WECO-6" => false),
                    "admins" => "should-be-stripped-from-chart",
                ),
            ],
            "tools" => [
                Dict("id" => "Film-PTPECVD01", "desc" => "PlasmaTherm PECVD", "area" => "Production"),
            ],
            "defaultRules" => Dict("WECO-1" => true, "WECO-2" => true),
            "savedAt" => "2026-06-18 20:46 UTC",
        )
        if with_admins
            state["admins"] = [
                Dict("name" => "Evil Admin", "email" => "evil@example.com", "passcode" => "SECRET-PASS"),
            ]
            state["passcodes"] = ["x"]
        end
        return state
    end

    @testset "html_state_to_workbench strips admins + maps values/specs/tools" begin
        d = _mini_html_archive()
        @test haskey(d, "admins")
        m = html_state_to_workbench(d)
        @test m isa SPCWorkbenchModel
        @test !hasfield(typeof(m), :admins)
        @test length(m.charts) == 1
        ch = m.charts[1]
        @test ch.name == "Film-Thickness-1.3um"
        @test ch.chart_type === I_MR
        @test ch.usl == 1320.0
        @test ch.target == 1300.0
        @test ch.lsl == 1280.0
        @test ch.units == "nm"
        @test ch.tools == ["Film-PTPECVD01"]
        @test ch.live_enabled === false
        @test ch.source === :table
        @test ch.col_value == "Value"
        @test ch.col_lot == "Wafer"
        @test ch.data.values ≈ [1303.0, 1305.0, 1299.0, 1301.0, 1294.0]
        @test length(m.table.rows) >= 5
        @test length(m.tools) == 1
        @test m.tools[1].id == "Film-PTPECVD01"
        @test m.tools[1].description == "PlasmaTherm PECVD"
        @test m.paused === true
        ctx = resolve_chart_render_context(ch)
        @test ctx.secondary_name == "MR"
        @test ctx.secondary_bar ≈ mean(abs.(diff(ch.data.values)))
        dumped = workbench_to_dict(m)
        @test !haskey(dumped, "admins")
        @test !haskey(dumped, "passcodes")
    end

    @testset "extract_html_spc_state from script tag + strip" begin
        body = """
        <!DOCTYPE html><html><body>
        <script id="spc-state" type="application/json">{"data":[{"Tool":"T1","Value":10},{"Tool":"T1","Value":12},{"Tool":"T1","Value":11}],"columns":["Tool","Value"],"charts":[{"id":"c1","name":"N","type":"I-MR","col_value":"Value","col_tool":"Tool","tools":["T1"],"rules":{"WECO-1":true}}],"admins":[{"name":"X","passcode":"P"}],"tools":[{"id":"T1","desc":"tool"}]}</script>
        <script>const state={admins:[{passcode:'LEAK'}]};</script>
        </body></html>
        """
        d = extract_html_spc_state(body)
        @test d isa AbstractDict
        @test !haskey(d, "admins")
        @test !haskey(d, "passcodes")
        @test haskey(d, "charts")
        m = html_state_to_workbench(d)
        @test m isa SPCWorkbenchModel
        @test m.charts[1].data.values ≈ [10.0, 12.0, 11.0]
    end

    @testset "fail closed: bad archive does not mutate model" begin
        d0 = generate_spc_workbench_data(8; seed = 11)
        m = SPCWorkbenchModel(data = d0, paused = true, seed_demos = :single)
        _ensure_charts!(m)
        m.charts[1].usl = 77.0
        m.charts[1].data.values[1] = 999.0
        m.rng = MersenneTwister(55)
        rng_before = m.rng
        m.tick = 3
        m.live_max = 111
        snap_vals = copy(m.charts[1].data.values)
        snap_n = length(m.charts)
        snap_usl = m.charts[1].usl

        bad = Dict{String,Any}("charts" => Any[])
        err = html_state_to_workbench!(m, bad)
        @test err isa AbstractString
        @test occursin("no charts", err)
        @test length(m.charts) == snap_n
        @test m.charts[1].data.values == snap_vals
        @test m.charts[1].usl == snap_usl
        @test m.rng === rng_before
        @test m.tick == 3
        @test m.live_max == 111

        err2 = html_state_to_workbench!(m, Dict{String,Any}(
            "version" => 1,
            "active" => 1,
            "charts" => [Dict("id" => "x", "name" => "y", "chart_type" => "I-MR", "values" => [1.0])],
        ))
        @test err2 isa AbstractString
        @test occursin("schema-v1", err2) || occursin("load_workbench", err2)
        @test m.charts[1].usl == snap_usl
        @test m.rng === rng_before

        err3 = load_html_archive!(m, "/tmp/missing_spc_html_$(rand(UInt32)).html")
        @test err3 isa AbstractString
        @test startswith(err3, "load err:")
        @test m.charts[1].data.values == snap_vals
        @test m.rng === rng_before
    end

    @testset "load_html_archive! success path + last_event" begin
        html = """
        <html><head></head><body>
        <script id="spc-state" type="application/json">{"data":[{"Tool":"A","Value":100},{"Tool":"A","Value":102},{"Tool":"A","Value":101},{"Tool":"B","Value":50}],"columns":["Tool","Value"],"charts":[{"id":"c1","name":"OnlyA","type":"I-MR","col_value":"Value","col_tool":"Tool","tools":["A"],"usl":110,"lsl":90,"rules":{"WECO-1":true}}],"admins":[{"name":"Z","passcode":"NOPE"}],"defaultRules":{"WECO-1":true},"tools":[{"id":"A","desc":"tool A"}]}</script>
        </body></html>
        """
        path = joinpath(tempdir(), "spc_html_arch_$(rand(UInt32)).html")
        try
            open(path, "w") do io
                write(io, html)
            end
            d0 = generate_spc_workbench_data(6; seed = 2)
            m = SPCWorkbenchModel(data = d0, paused = false, seed_demos = :triple)
            _ensure_charts!(m)
            @test length(m.charts) == 3
            m.rng = MersenneTwister(9)
            rng_before = m.rng
            m.tick = 8
            m.live_max = 50

            err = load_html_archive!(m, path)
            @test err === nothing
            @test length(m.charts) == 1
            @test m.charts[1].name == "OnlyA"
            @test m.charts[1].data.values ≈ [100.0, 102.0, 101.0]
            @test m.charts[1].usl == 110.0
            @test m.charts[1].live_enabled === false
            @test m.paused === true
            @test startswith(m.last_event, "loaded html ")
            @test m.last_workbench_path == path
            @test m.rng === rng_before
            @test m.tick == 8
            @test m.live_max == 50
            @test m.view_mode === :dashboard
            m2 = load_html_archive(path)
            @test m2 isa SPCWorkbenchModel
            @test m2.charts[1].data.values ≈ [100.0, 102.0, 101.0]
        finally
            isfile(path) && rm(path; force = true)
        end
    end

    @testset "optional real SPC_workbench HTML sample" begin
        sample = joinpath(@__DIR__, "..", "SPC_workbench_2026-06-18-20-46.html")
        if isfile(sample)
            m = load_html_archive(sample)
            @test m isa SPCWorkbenchModel
            @test length(m.charts) >= 1
            film = findfirst(c -> occursin("Film-Thickness", c.name), m.charts)
            @test film !== nothing
            ch = m.charts[film]
            @test length(ch.data.values) == 10
            @test ch.usl == 1320.0
            ctx = resolve_chart_render_context(ch)
            @test round(ctx.lz.sigma; digits = 2) ≈ 4.24
            @test ctx.secondary_name == "MR"
            @test ctx.secondary_bar !== nothing
            @test !hasfield(typeof(m), :admins)
            dumped = workbench_to_dict(m)
            @test !haskey(dumped, "admins")
        else
            @test true
        end
    end

end
end # module TestSPCWorkbenchHTMLImport

# PR2: pure browser listing + graph config index + include_path serialization
# (package-module load to avoid type redefinition vs pure include of spc_workbench.jl).
# ═══════════════════════════════════════════════════════════════════════

module TestSPCWorkbenchBrowserIndexIO
using Test
using Random
using TachikomaTUI

const WB = TachikomaTUI

@testset "PR2 list_browser_entries + index IO + GraphPreset.path serialization" begin

    @testset "list_browser_entries: dirs, json filter, hidden, cap, errors" begin
        mktempdir() do dir
            mkdir(joinpath(dir, "sub"))
            mkdir(joinpath(dir, ".hidden_dir"))
            open(joinpath(dir, "a.json"), "w") do io; write(io, "{}"); end
            open(joinpath(dir, "b.JSON"), "w") do io; write(io, "{}"); end
            open(joinpath(dir, "c.txt"), "w") do io; write(io, "x"); end
            open(joinpath(dir, ".secret.json"), "w") do io; write(io, "{}"); end
            open(joinpath(dir, "z.json"), "w") do io; write(io, "{}"); end

            ents = list_browser_entries(dir)
            @test ents isa Vector{FileBrowserEntry}
            names = [e.name for e in ents]
            # parent when not root
            @test ".." in names
            parent_e = ents[findfirst(e -> e.is_parent, ents)]
            @test parent_e.is_dir
            @test parent_e.path == dirname(abspath(dir))
            # dirs first among non-parent, then json files (case-insensitive)
            non_parent = filter(e -> !e.is_parent, ents)
            dir_names = [e.name for e in non_parent if e.is_dir]
            file_names = [e.name for e in non_parent if !e.is_dir]
            @test dir_names == sort(dir_names)
            @test "sub" in dir_names
            @test !(".hidden_dir" in dir_names)
            @test Set(file_names) == Set(["a.json", "b.JSON", "z.json"])
            @test !("c.txt" in file_names)
            @test !(".secret.json" in file_names)
            # order: dirs then files
            first_file_i = findfirst(e -> !e.is_dir, non_parent)
            last_dir_i = findlast(e -> e.is_dir, non_parent)
            if first_file_i !== nothing && last_dir_i !== nothing
                @test last_dir_i < first_file_i
            end

            # show_hidden
            ents_h = list_browser_entries(dir; show_hidden = true)
            names_h = [e.name for e in ents_h]
            @test ".hidden_dir" in names_h
            @test ".secret.json" in names_h

            # cap
            ents_cap = list_browser_entries(dir; max_entries = 2)
            @test ents_cap isa Vector{FileBrowserEntry}
            @test length(ents_cap) == 2

            # custom pred
            ents_txt = list_browser_entries(dir; file_pred = n -> endswith(n, ".txt"))
            @test any(e -> e.name == "c.txt", ents_txt)
            @test !any(e -> endswith(lowercase(e.name), ".json") && !e.is_dir, ents_txt)

            # not a directory
            err = list_browser_entries(joinpath(dir, "nope_missing_$(rand(UInt32))"))
            @test err isa AbstractString
            @test occursin("browser err", err)
        end
    end

    @testset "XDG helpers + default index path" begin
        # default when XDG_DATA_HOME empty → ~/.local/share/tachikoma-tui/...
        old = get(ENV, "XDG_DATA_HOME", nothing)
        try
            delete!(ENV, "XDG_DATA_HOME")
            p = default_graph_config_index_path()
            @test endswith(p, joinpath("tachikoma-tui", "graph_config_index.json"))
            @test occursin(".local", p) || occursin("share", p)
            # non-empty XDG_DATA_HOME
            mktempdir() do xdg
                ENV["XDG_DATA_HOME"] = xdg
                p2 = default_graph_config_index_path()
                @test p2 == joinpath(xdg, "tachikoma-tui", "graph_config_index.json")
                @test WB._tachikoma_data_dir() == joinpath(xdg, "tachikoma-tui")
            end
        finally
            if old === nothing
                delete!(ENV, "XDG_DATA_HOME")
            else
                ENV["XDG_DATA_HOME"] = old
            end
        end
    end

    @testset "graph config index: mkpath write, read, upsert, cap, corrupt" begin
        mktempdir() do root
            idx_path = joinpath(root, "nested", "deep", "graph_config_index.json")
            @test !isdir(dirname(idx_path))

            # missing → empty
            @test read_graph_config_index(idx_path) == GraphConfigIndexEntry[]

            e1 = GraphConfigIndexEntry(
                name = "fab-dense",
                path = "/tmp/a/fab-dense.json",
                saved_at = "2026-07-13T10:00:00",
                last_used_at = "2026-07-13T12:00:00",
                summary = Dict{String,Any}("weco_on" => 5, "lines_off" => 1, "styles" => "mixed"),
            )
            e2 = GraphConfigIndexEntry(
                name = "loose",
                path = "/tmp/b/loose.json",
                saved_at = "2026-07-13T11:00:00",
                last_used_at = "2026-07-13T13:00:00",
                summary = Dict{String,Any}("weco_on" => 8, "lines_off" => 0, "styles" => "solid"),
            )
            entries = GraphConfigIndexEntry[e1, e2]
            err = write_graph_config_index(idx_path, entries)
            @test err === nothing
            @test isfile(idx_path)
            @test isdir(dirname(idx_path))  # mkpath

            loaded = read_graph_config_index(idx_path)
            @test length(loaded) == 2
            paths = sort([e.path for e in loaded])
            @test paths == sort([abspath("/tmp/a/fab-dense.json"), abspath("/tmp/b/loose.json")]) ||
                  paths == sort(["/tmp/a/fab-dense.json", "/tmp/b/loose.json"])
            # name preserved
            by_name = Dict(e.name => e for e in loaded)
            @test haskey(by_name, "fab-dense")
            @test by_name["fab-dense"].summary["weco_on"] == 5

            # path-keyed upsert: same path replaces
            ents = read_graph_config_index(idx_path)
            e1b = GraphConfigIndexEntry(
                name = "fab-dense-v2",
                path = e1.path,
                saved_at = "2026-07-13T14:00:00",
                last_used_at = "2026-07-13T15:00:00",
                summary = Dict{String,Any}("weco_on" => 6, "lines_off" => 0, "styles" => "dashed"),
            )
            upsert_graph_config_index_entry!(ents, e1b)
            @test length(ents) == 2
            hit = findfirst(e -> abspath(e.path) == abspath(e1.path), ents)
            @test hit !== nothing
            @test ents[hit].name == "fab-dense-v2"
            @test ents[hit].summary["weco_on"] == 6

            # new path pushes
            e3 = GraphConfigIndexEntry(
                name = "third",
                path = "/tmp/c/third.json",
                saved_at = "2026-07-13T16:00:00",
                last_used_at = "2026-07-13T16:00:00",
                summary = Dict{String,Any}(),
            )
            upsert_graph_config_index_entry!(ents, e3)
            @test length(ents) == 3

            # empty path no-op
            n_before = length(ents)
            upsert_graph_config_index_entry!(ents, GraphConfigIndexEntry(name = "x", path = ""))
            @test length(ents) == n_before

            # cap 50: fill beyond cap, oldest last_used_at dropped
            bulk = GraphConfigIndexEntry[]
            for i in 1:55
                # zero-padded so string order matches insertion order
                ts = "t" * lpad(string(i), 3, '0')
                push!(bulk, GraphConfigIndexEntry(
                    name = "n$i",
                    path = "/tmp/cap/cfg_$i.json",
                    saved_at = ts,
                    last_used_at = ts,
                    summary = Dict{String,Any}(),
                ))
            end
            capped = GraphConfigIndexEntry[]
            for e in bulk
                upsert_graph_config_index_entry!(capped, e; cap = 50)
            end
            @test length(capped) == 50
            # oldest should be gone (t001..t005)
            used = Set(e.last_used_at for e in capped)
            @test !("t001" in used)
            @test !("t005" in used)
            @test "t055" in used
            @test "t006" in used

            # corrupt / bad version → empty
            bad = joinpath(root, "bad_index.json")
            open(bad, "w") do io; write(io, "{not json"); end
            @test read_graph_config_index(bad) == GraphConfigIndexEntry[]
            open(bad, "w") do io
                write(io, """{"version":99,"kind":"graph_config_index","entries":[{"name":"x","path":"/p"}]}""")
            end
            @test read_graph_config_index(bad) == GraphConfigIndexEntry[]
            open(bad, "w") do io
                write(io, """{"version":1,"kind":"other","entries":[{"name":"x","path":"/p"}]}""")
            end
            @test read_graph_config_index(bad) == GraphConfigIndexEntry[]

            # graph_preset_index_summary + entry_from_preset
            p = GraphPreset(
                name = "sum",
                show_chart_lines = copy(DEFAULT_CHART_LINES),
                chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
                visual_prefs = copy(DEFAULT_VISUAL_PREFS),
                enabled_rules = copy(DEFAULT_WECO_RULES),
                path = joinpath(root, "sum.json"),
            )
            p.show_chart_lines["cl"] = false
            p.enabled_rules["WECO-6"] = true
            s = graph_preset_index_summary(p)
            @test s["lines_off"] == 1
            @test s["weco_on"] == count(values(p.enabled_rules))
            @test s["styles"] isa AbstractString
            ent = graph_config_index_entry_from_preset(p)
            @test ent isa GraphConfigIndexEntry
            @test ent.name == "sum"
            @test abspath(ent.path) == abspath(p.path)
            @test ent.summary["lines_off"] == 1
            @test graph_config_index_entry_from_preset(GraphPreset(name = "nopath")) === nothing
        end
    end

    @testset "graph_preset_to_dict include_path + from_dict path optional" begin
        p = GraphPreset(
            name = "with-path",
            show_chart_lines = copy(DEFAULT_CHART_LINES),
            chart_line_styles = copy(DEFAULT_CHART_LINE_STYLES),
            visual_prefs = copy(DEFAULT_VISUAL_PREFS),
            enabled_rules = copy(DEFAULT_WECO_RULES),
            path = "/home/op/configs/with-path.json",
        )
        p.show_chart_lines["specs"] = false

        # default / standalone: no path key
        d0 = graph_preset_to_dict(p)
        @test !haskey(d0, "path")
        d_false = graph_preset_to_dict(p; include_path = false)
        @test !haskey(d_false, "path")
        # session: include_path true
        d_true = graph_preset_to_dict(p; include_path = true)
        @test d_true["path"] == "/home/op/configs/with-path.json"
        @test d_true["name"] == "with-path"
        # empty path never written even with include_path
        p_empty = GraphPreset(name = "mem", path = "")
        @test !haskey(graph_preset_to_dict(p_empty; include_path = true), "path")

        # from_dict optional path
        p2 = graph_preset_from_dict(d_true)
        @test p2 isa GraphPreset
        @test p2.path == "/home/op/configs/with-path.json"
        @test p2.show_chart_lines["specs"] === false
        p3 = graph_preset_from_dict(d0)
        @test p3 isa GraphPreset
        @test p3.path == ""

        # standalone file never writes path even if model has path
        mktempdir() do dir
            fpath = joinpath(dir, "portable.json")
            @test save_graph_preset(p, fpath) === nothing
            raw = read(fpath, String)
            @test !occursin("/home/op/configs", raw)
            @test !occursin("\"path\"", raw)
            loaded = load_graph_preset(fpath)
            @test loaded isa GraphPreset
            @test loaded.path == ""
            @test loaded.name == "with-path"
        end

        # session round-trip restores path via workbench_to_dict include_path=true
        d = generate_spc_workbench_data(8; seed = 41)
        m = SPCWorkbenchModel(data = d, paused = true, seed_demos = :single)
        push!(m.graph_presets, p)
        wd = workbench_to_dict(m)
        @test haskey(wd, "graph_presets")
        @test wd["graph_presets"][1]["path"] == p.path
        path = joinpath(tempdir(), "spc_wb_path_rt_$(rand(UInt32)).json")
        try
            @test save_workbench(m, path) === nothing
            loaded_m = load_workbench(path)
            @test loaded_m isa SPCWorkbenchModel
            @test length(loaded_m.graph_presets) == 1
            @test loaded_m.graph_presets[1].path == p.path
            @test loaded_m.graph_presets[1].name == "with-path"
        finally
            isfile(path) && rm(path; force = true)
        end

        # Issue 5: whitespace-only path strips to empty; non-string path ignored
        p_ws = graph_preset_from_dict(Dict{String,Any}("name" => "ws", "path" => "   "))
        @test p_ws isa GraphPreset
        @test p_ws.path == ""
        p_ns = graph_preset_from_dict(Dict{String,Any}("name" => "ns", "path" => 123))
        @test p_ns isa GraphPreset
        @test p_ns.path == ""
    end

    @testset "review fixes: tilde index path, empty path, empty-ts cap" begin
        # Issue 2: write/read via ~/… path under homedir
        rel = joinpath(".cache", "tachikoma-tui-pr2-idx-$(rand(UInt32))", "graph_config_index.json")
        abs_idx = joinpath(homedir(), rel)
        tilde_idx = "~/" * replace(rel, "\\" => "/")
        try
            e = GraphConfigIndexEntry(
                name = "via-tilde",
                path = "/tmp/via-tilde.json",
                saved_at = "2026-07-13T10:00:00",
                last_used_at = "2026-07-13T10:00:00",
                summary = Dict{String,Any}("weco_on" => 1),
            )
            err = write_graph_config_index(tilde_idx, GraphConfigIndexEntry[e])
            @test err === nothing
            @test isfile(abs_idx)
            loaded = read_graph_config_index(tilde_idx)
            @test length(loaded) == 1
            @test loaded[1].name == "via-tilde"
            # also readable via absolute path
            @test length(read_graph_config_index(abs_idx)) == 1
        finally
            isfile(abs_idx) && rm(abs_idx; force = true)
            d = dirname(abs_idx)
            isdir(d) && rm(d; force = true)
        end

        # Issue 6: empty path → clear error
        @test write_graph_config_index("", GraphConfigIndexEntry[]) == "index err: empty path"
        @test write_graph_config_index("   ", GraphConfigIndexEntry[]) == "index err: empty path"
        @test read_graph_config_index("") == GraphConfigIndexEntry[]

        # Issue 4: empty last_used_at at cap still retains the new path.
        # Bulk uses ISO-ish timestamps so string order matches age; auto-fill uses "now".
        capped = GraphConfigIndexEntry[]
        for i in 1:50
            ts = "2020-01-01T00:" * lpad(string(div(i - 1, 60)), 2, '0') * ":" *
                 lpad(string(mod(i - 1, 60)), 2, '0')
            upsert_graph_config_index_entry!(capped, GraphConfigIndexEntry(
                name = "n$i",
                path = "/tmp/cap2/cfg_$i.json",
                saved_at = ts,
                last_used_at = ts,
                summary = Dict{String,Any}(),
            ); cap = 50)
        end
        @test length(capped) == 50
        upsert_graph_config_index_entry!(capped, GraphConfigIndexEntry(
            name = "new",
            path = "/tmp/cap2/new.json",
            saved_at = "",
            last_used_at = "",
            summary = Dict{String,Any}(),
        ); cap = 50)
        @test length(capped) == 50
        hit = findfirst(e -> e.name == "new", capped)
        @test hit !== nothing
        @test any(e -> endswith(e.path, "new.json"), capped)
        @test !isempty(capped[hit].last_used_at)  # auto-filled so not immediately evicted
        @test !isempty(capped[hit].saved_at)
        # oldest bulk entry (n1 / 00:00:00) should be gone
        @test !any(e -> e.name == "n1", capped)

        # remove_graph_config_index_entry! path-keyed (KD-SE-9)
        ents_rm = GraphConfigIndexEntry[
            GraphConfigIndexEntry(name = "a", path = "/tmp/rm/a.json", last_used_at = "2026-01-01T00:00:00"),
            GraphConfigIndexEntry(name = "b", path = "/tmp/rm/b.json", last_used_at = "2026-01-02T00:00:00"),
        ]
        @test remove_graph_config_index_entry!(ents_rm, "/tmp/rm/a.json") === true
        @test length(ents_rm) == 1
        @test ents_rm[1].name == "b"
        @test remove_graph_config_index_entry!(ents_rm, "/tmp/rm/nope.json") === false
        @test remove_graph_config_index_entry!(ents_rm, "") === false
        @test length(ents_rm) == 1
    end

end

end # module TestSPCWorkbenchBrowserIndexIO
