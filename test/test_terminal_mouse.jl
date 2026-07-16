using Test
using Tachikoma
using TachikomaTUI

@testset "terminal mouse (Windows + Linux/macOS)" begin
    @testset "full tracking sequences include 1003 hover mode" begin
        @test mouse_seq_is_full_tracking(APP_MOUSE_ON)
        @test mouse_seq_is_full_off(APP_MOUSE_OFF)
        # Regression: Tachikoma's stock MOUSE_ON lacks any-event tracking
        stock = "\e[?1000h\e[?1002h\e[?1006h"
        @test !mouse_seq_is_full_tracking(stock)
        @test occursin("1003h", APP_MOUSE_ON)
        @test occursin("1003l", APP_MOUSE_OFF)
        @test occursin("1000h", APP_MOUSE_ON)
        @test occursin("1002h", APP_MOUSE_ON)
        @test occursin("1006h", APP_MOUSE_ON)
    end

    @testset "enable_app_mouse! writes full on sequence to IO" begin
        io = IOBuffer()
        enable_app_mouse!(io)
        s = String(take!(io))
        @test mouse_seq_is_full_tracking(s)
        @test s == APP_MOUSE_ON
    end

    @testset "disable_app_mouse! writes full off sequence to IO" begin
        io = IOBuffer()
        disable_app_mouse!(io)
        s = String(take!(io))
        @test mouse_seq_is_full_off(s)
        @test s == APP_MOUSE_OFF
    end

    @testset "Tachikoma parse_sgr_mouse understands hover (base 35)" begin
        params = Vector{UInt8}(codeunits("<35;10;5"))
        evt = Tachikoma.parse_sgr_mouse(params, 'M')
        @test evt isa Tachikoma.MouseEvent
        @test evt.action == Tachikoma.mouse_move
        @test evt.button == Tachikoma.mouse_none
        @test evt.x == 10
        @test evt.y == 5
    end

    @testset "Tachikoma parse_sgr_mouse left click press/release" begin
        press = Tachikoma.parse_sgr_mouse(Vector{UInt8}(codeunits("<0;20;8")), 'M')
        @test press isa Tachikoma.MouseEvent
        @test press.action == Tachikoma.mouse_press
        @test press.button == Tachikoma.mouse_left
        rel = Tachikoma.parse_sgr_mouse(Vector{UInt8}(codeunits("<0;20;8")), 'm')
        @test rel.action == Tachikoma.mouse_release
        @test rel.button == Tachikoma.mouse_left
    end

    @testset "workbench init! enables mouse when helper present" begin
        d = generate_spc_workbench_data(8; seed = 1)
        m = SPCWorkbenchModel(data = d, paused = true)
        io = IOBuffer()
        t = Tachikoma.Terminal(io = io, size = (rows = 24, cols = 80))
        t.mouse_enabled = false
        Tachikoma.init!(m, t)
        @test t.mouse_enabled == true
        s = String(take!(io))
        @test mouse_seq_is_full_tracking(s)
        @test occursin("mouse on", m.last_event)
    end

    @testset "platform helpers do not throw on this OS" begin
        io = IOBuffer()
        @test enable_app_mouse!(io) === nothing
        @test disable_app_mouse!(io) === nothing
        # Windows path mutates console mode; Linux returns nothing from prepare
        if Sys.iswindows()
            @test TachikomaTUI._windows_console_prepare_mouse!() isa Union{Nothing,UInt32}
        else
            @test TachikomaTUI._windows_console_prepare_mouse!() === nothing
        end
    end
end
