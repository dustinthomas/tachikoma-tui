using Test
using Tachikoma
using TachikomaTUI

const T = Tachikoma

@testset "Tutorial path recording helpers (R3–R4)" begin
    @testset "make_blank_workbench" begin
        m = make_blank_workbench()
        @test m.seed_demos === :none
        @test m.paused
        @test length(m.charts) == 1
        @test m.charts[1].name == "Primary"
        @test isempty(m.charts[1].data.values)
        @test isempty(m.tools)
        @test isempty(m.params)
    end

    @testset "make_pecvd_tutorial_workbench" begin
        m = make_pecvd_tutorial_workbench()
        @test length(m.charts) == 3
        @test m.charts[1].name == "Oxide Thickness 1.3um"
        @test m.charts[2].name == "Refractive Index"
        @test m.charts[3].name == "HSQ Thickness"
        @test length(m.charts[1].data.values) == 40
        @test length(m.charts[2].data.values) == 40
        @test length(m.charts[3].data.values) == 40
        @test m.charts[1].target == 1300.0
        @test m.charts[2].target == 1.46
        @test m.charts[3].target == 600.0
        @test any(t -> t.id == "Film-PTPECVD01", m.tools)
        @test m.charts[1].tools == ["Film-PTPECVD01"]
        @test m.paused
    end

    @testset "record_blank_workbench_demo writes .tach" begin
        path = joinpath(mktempdir(), "blank.tach")
        out = record_blank_workbench_demo(path; width = 80, height = 24, fps = 10)
        @test out == path
        @test isfile(path)
        w, h, cells, ts, px = T.load_tach(path)
        @test w == 80
        @test h == 24
        @test length(cells) >= 10
        @test length(ts) == length(cells)
    end

    @testset "record_pecvd_tutorial_demo writes .tach" begin
        path = joinpath(mktempdir(), "pecvd.tach")
        out = record_pecvd_tutorial_demo(path; width = 80, height = 24, fps = 10)
        @test out == path
        @test isfile(path)
        w, h, cells, ts, px = T.load_tach(path)
        @test length(cells) >= 10
        @test length(ts) == length(cells)
    end
end
