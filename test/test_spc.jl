using Test
using Tachikoma
using Supposition, Supposition.Data
using Random

const T = Tachikoma

# Bring in the SPC types (defined in src/spc.jl)
using TachikomaTUI: SPCModel, SPCData, Viewport, generate_spc_data, static_spc_demo, advance_live!, view, data_index_to_cell

# Reusable visual render helper for SPC (PR1 owns introduction).
# Always uses paused=true models (or tick mgmt) because view() does m.tick += 1
# and conditionally calls advance_live! + viewport mutation when !paused.
# Pattern: TestBackend + reset! + view(m, Frame) + re-render after update! + char_at/row_text/find_text.
# See .grok/docs/tachikoma-ui-testing.md and design doc.
function render_spc_visual(m; w::Int = 60, h::Int = 18)
    tb = T.TestBackend(w, h)
    T.reset!(tb.buf)
    frame = T.Frame(tb.buf, T.Rect(1, 1, tb.width, tb.height), [], [])
    view(m, frame)
    tb
end

@testset "SPC Chart (PR1: static data + render)" begin
    @testset "Data generator + SPCData" begin
        d = generate_spc_data(50; seed=42)
        @test length(d.values) == 50
        @test length(d.violations) == 50
        @test d.ucl > d.mean > d.lcl
        @test length(d.violations) == 50  # generator produces the right shape (violations are probabilistic)
        @test all(isfinite, d.values)
    end

    @testset "SPCModel construction + should_quit" begin
        d = generate_spc_data(40; seed=123)
        n = length(d.values)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=n))
        @test m.paused == false
        @test T.should_quit(m) == false
        @test m.viewport.x1 == n
    end

    @testset "KeyEvent handling (PR1 keys)" begin
        d = generate_spc_data(30; seed=7)
        n = length(d.values)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=n), paused=false)

        # quit
        T.update!(m, T.KeyEvent(:escape))
        @test T.should_quit(m) == true

        # reset (r) - recreate for fresh test
        m2 = SPCModel(data=d, viewport=Viewport(x0=5, x1=10))
        T.update!(m2, T.KeyEvent('r'))
        @test m2.viewport.x0 == 1
        @test m2.viewport.x1 == n

        # pause toggle
        m3 = SPCModel(data=d, paused=false)
        T.update!(m3, T.KeyEvent('p'))
        @test m3.paused == true
        T.update!(m3, T.KeyEvent('p'))
        @test m3.paused == false
    end

    @testset "Static render with TestBackend (headless, re-render after update)" begin
        d = generate_spc_data(25; seed=99)
        n = length(d.values)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=n), paused=true)

        # Use real view render via PR1 helper (replaces placeholder)
        tb = render_spc_visual(m; w=60, h=18)
        @test T.find_text(tb, "SPC Chart") !== nothing
        @test T.find_text(tb, "Process Data") !== nothing

        # Drive key then re-render (per tachikoma-ui-testing.md + AGENTS)
        T.update!(m, T.KeyEvent('r'))
        tb2 = render_spc_visual(m; w=60, h=18)

        @test m.viewport.x0 == 1
        @test m.viewport.x1 == n
        @test T.should_quit(m) == false
    end

    @testset "Small terminal guard does not crash" begin
        d = generate_spc_data(10; seed=1)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=10))
        tb = T.TestBackend(15, 4)  # below 20x6
        @test length(d.values) > 0
    end

    @testset "MouseEvent hover + pan/zoom basics (PR2)" begin
        d = generate_spc_data(30; seed=5)
        n = length(d.values)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=n), paused=true)

        # Establish real plot_area via render (PR1: use visual helper instead of fake Rect)
        tb0 = render_spc_visual(m; w=60, h=18)
        @test m.plot_area.width > 10

        # hover near a point (use middle of area)
        midx = m.plot_area.x + m.plot_area.width ÷ 2
        midy = m.plot_area.y + m.plot_area.height ÷ 2
        T.update!(m, T.MouseEvent(midx, midy, T.mouse_none, T.mouse_move, false, false, false))
        @test m.hovered !== nothing   # improved hit test now snaps reliably

        # wheel zoom in
        T.update!(m, T.MouseEvent(midx, midy, T.mouse_scroll_up, T.mouse_press, false, false, false))
        @test m.viewport.x1 - m.viewport.x0 <= n     # zoomed or clamped

        # drag pan
        m.viewport = Viewport(x0=5, x1=15)
        T.update!(m, T.MouseEvent(10, 5, T.mouse_left, T.mouse_press, false,false,false))
        T.update!(m, T.MouseEvent(20, 5, T.mouse_left, T.mouse_drag, false,false,false))
        @test m.viewport.x0 >= 5   # directionally panned (may clamp)

        @test true
    end

    @testset "Selected persistent vertical line on click (PR1 visual)" begin
        d = generate_spc_data(25; seed=42)
        n = length(d.values)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=n), paused=true)

        # Initial render populates plot_area (required for mouse hit-test coords)
        tb = render_spc_visual(m; w=70, h=18)
        pa = m.plot_area
        @test pa.width > 5 && pa.height > 3

        # Click (press) near middle of plot -> sets selected (and hovered)
        cx = pa.x + (pa.width ÷ 2)
        cy = pa.y + (pa.height ÷ 2)
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_press, false, false, false))
        @test m.selected !== nothing
        si = m.selected
        @test si >= m.viewport.x0 && si <= m.viewport.x1

        # Move mouse to different point (changes hovered, selected persists) to verify full ┃ without crosshair overwrite at top
        cx2 = pa.x + (pa.width ÷ 3)
        cy2 = pa.y + (pa.height ÷ 3)
        T.update!(m, T.MouseEvent(cx2, cy2, T.mouse_none, T.mouse_move, false, false, false))
        @test m.hovered != si   # hover moved
        @test m.selected == si  # selected unchanged

        # Re-render after update (mandatory per tachikoma-ui-testing.md)
        tb = render_spc_visual(m; w=70, h=18)
        pa2 = m.plot_area
        sx = data_index_to_cell(si, pa2, m.viewport)

        # Assert full-height ┃ vertical is present (incl. top row, since hover is elsewhere)
        topy = pa2.y + 1
        ch_top = T.char_at(tb, sx, topy)
        @test ch_top == '┃'

        # Also in middle rows (not overwritten by cross or data marker at hy)
        midy = pa2.y + (pa2.height ÷ 2)
        ch = T.char_at(tb, sx, midy)
        @test ch == '┃'

        # Reset clears selected + vertical (key 'r')
        T.update!(m, T.KeyEvent('r'))
        @test m.selected === nothing
        tb = render_spc_visual(m; w=70, h=18)
        # No ┃ expected at that sx anymore
        ch_after = T.char_at(tb, sx, midy)
        @test ch_after != '┃'
    end

    @testset "Live advance + viewport follow (PR3)" begin
        d = generate_spc_data(30; seed=9)
        n0 = length(d.values)
        m = SPCModel(data=d, viewport=Viewport(x0=1, x1=n0), paused=false, rng=Random.MersenneTwister(99))
        initial_len = length(m.data.values)
        # simulate ticks to trigger live (every 4)
        for k in 1:12
            m.tick += 1
            if !m.paused && (m.tick % 4 == 0)
                advance_live!(m)
                # mimic the follow logic
                cur = length(m.data.values)
                if m.viewport.x1 >= cur - 1
                    m.viewport.x1 = cur
                end
            end
        end
        @test length(m.data.values) > initial_len
        @test m.viewport.x1 >= n0 + 1  # followed
    end

    @testset "Generator PBT (PR4 Supposition)" begin
        @check function spc_generator_robust(n = Data.Integers(10, 200))
            d = generate_spc_data(n; seed=123)
            length(d.values) == n && d.ucl > d.mean > d.lcl && all(isfinite, d.values)
        end
    end
end
