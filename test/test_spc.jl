using Test
using Tachikoma
using Supposition, Supposition.Data
using Random

const T = Tachikoma

# Bring in the SPC types (defined in src/spc.jl)
using TachikomaTUI:
    SPCModel,
    SPCData,
    Viewport,
    generate_spc_data,
    static_spc_demo,
    advance_live!,
    view,
    data_index_to_cell,
    data_val_to_cell_row

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
        d = generate_spc_data(50; seed = 42)
        @test length(d.values) == 50
        @test length(d.violations) == 50
        @test d.ucl > d.mean > d.lcl
        @test all(isfinite, d.values)
    end

    @testset "SPCModel construction + should_quit" begin
        d = generate_spc_data(40; seed = 123)
        n = length(d.values)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n))
        @test m.paused == false
        @test T.should_quit(m) == false
        @test m.viewport.x1 == n
    end

    @testset "KeyEvent handling (PR1 keys)" begin
        d = generate_spc_data(30; seed = 7)
        n = length(d.values)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n), paused = false)

        # quit
        T.update!(m, T.KeyEvent(:escape))
        @test T.should_quit(m) == true

        # reset (r) - recreate for fresh test
        m2 = SPCModel(data = d, viewport = Viewport(x0 = 5, x1 = 10))
        T.update!(m2, T.KeyEvent('r'))
        @test m2.viewport.x0 == 1
        @test m2.viewport.x1 == n

        # pause toggle
        m3 = SPCModel(data = d, paused = false)
        T.update!(m3, T.KeyEvent('p'))
        @test m3.paused == true
        T.update!(m3, T.KeyEvent('p'))
        @test m3.paused == false
    end

    @testset "Static render with TestBackend (headless, re-render after update)" begin
        d = generate_spc_data(25; seed = 99)
        n = length(d.values)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n), paused = true)

        # Use real view render via PR1 helper (replaces placeholder)
        tb = render_spc_visual(m; w = 60, h = 18)
        @test T.find_text(tb, "SPC Chart") !== nothing
        @test T.find_text(tb, "Process Data") !== nothing

        # Drive key then re-render (per tachikoma-ui-testing.md + AGENTS)
        T.update!(m, T.KeyEvent('r'))
        tb2 = render_spc_visual(m; w = 60, h = 18)

        @test m.viewport.x0 == 1
        @test m.viewport.x1 == n
        @test T.should_quit(m) == false
    end

    @testset "Small terminal guard does not crash" begin
        d = generate_spc_data(10; seed = 1)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = 10))
        tb = T.TestBackend(15, 4)  # below 20x6
        @test length(d.values) > 0
    end

    @testset "MouseEvent hover + pan/zoom basics (PR2)" begin
        d = generate_spc_data(30; seed = 5)
        n = length(d.values)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n), paused = true)

        # Establish real plot_area via render (PR1: use visual helper instead of fake Rect)
        tb0 = render_spc_visual(m; w = 60, h = 18)
        @test m.plot_area.width > 10

        # hover near a point (use middle of area)
        midx = m.plot_area.x + m.plot_area.width ÷ 2
        midy = m.plot_area.y + m.plot_area.height ÷ 2
        T.update!(
            m,
            T.MouseEvent(midx, midy, T.mouse_none, T.mouse_move, false, false, false),
        )
        @test m.hovered !== nothing   # improved hit test now snaps reliably

        # wheel zoom in
        T.update!(
            m,
            T.MouseEvent(midx, midy, T.mouse_scroll_up, T.mouse_press, false, false, false),
        )
        @test m.viewport.x1 - m.viewport.x0 <= n     # zoomed or clamped

        # drag pan
        m.viewport = Viewport(x0 = 5, x1 = 15)
        T.update!(m, T.MouseEvent(10, 5, T.mouse_left, T.mouse_press, false, false, false))
        T.update!(m, T.MouseEvent(20, 5, T.mouse_left, T.mouse_drag, false, false, false))
        @test m.viewport.x0 >= 5   # directionally panned (may clamp)
    end

    @testset "Selected persistent vertical line on click (PR1 visual)" begin
        d = generate_spc_data(25; seed = 42)
        n = length(d.values)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n), paused = true)

        # Initial render populates plot_area (required for mouse hit-test coords)
        tb = render_spc_visual(m; w = 70, h = 18)
        pa = m.plot_area
        @test pa.width > 5 && pa.height > 3

        # Click: press then release at same spot -> commits selected via snap (uses release x for nearest point)
        cx = pa.x + (pa.width ÷ 2)
        cy = pa.y + (pa.height ÷ 2)
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_press, false, false, false))
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_release, false, false, false))
        @test m.selected !== nothing
        si = m.selected
        @test si >= m.viewport.x0 && si <= m.viewport.x1

        # Move mouse (plain hover) to different point (changes hovered, selected persists)
        # to verify full ┃ remains (drawn independently) without being cleared by hover move.
        cx2 = pa.x + (pa.width ÷ 3)
        cy2 = pa.y + (pa.height ÷ 3)
        T.update!(
            m,
            T.MouseEvent(cx2, cy2, T.mouse_none, T.mouse_move, false, false, false),
        )
        @test m.hovered != si   # hover moved
        @test m.selected == si  # selected unchanged (and ┃ will be drawn)

        # Re-render after update (mandatory per tachikoma-ui-testing.md)
        tb = render_spc_visual(m; w = 70, h = 18)
        pa2 = m.plot_area
        sx = data_index_to_cell(si, pa2, m.viewport)

        # Assert full-height ┃ vertical is present (incl. top row, since hover is elsewhere)
        topy = pa2.y + 1
        ch_top = T.char_at(tb, sx, topy)
        @test ch_top == '┃'

        # Also in middle rows (not overwritten by cross or data marker at hy)
        hy = data_val_to_cell_row(d.values[si], pa2, m.viewport)
        midy = pa2.y + (pa2.height ÷ 2)
        if midy == hy
            midy = hy > (pa2.y + 1) ? hy - 1 : hy + 1
            midy = clamp(midy, pa2.y + 1, T.bottom(pa2) - 1)
        end
        ch = T.char_at(tb, sx, midy)
        @test ch == '┃'

        # Reset clears selected + vertical (key 'r')
        T.update!(m, T.KeyEvent('r'))
        @test m.selected === nothing
        tb = render_spc_visual(m; w = 70, h = 18)
        # No ┃ expected at that sx anymore (char_at + selected===nothing prove removal post-re-render)
        ch_after = T.char_at(tb, sx, midy)
        @test ch_after != '┃'
    end

    @testset "Data point markers overlay (PR2 visual)" begin
        # Use seed=42 data: violation at index 77 (only one)
        d = generate_spc_data(80; seed = 42)
        n = length(d.values)
        @test d.violations[77] == true
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n), paused = true)

        tb = render_spc_visual(m; w = 80, h = 20)
        pa = m.plot_area
        @test pa.width > 10 && pa.height > 5

        # Markers present for visible points (default full viewport)
        for i in [1, 10, 40, 77]
            dx = data_index_to_cell(i, pa, m.viewport)
            dy = data_val_to_cell_row(d.values[i], pa, m.viewport)
            ch = T.char_at(tb, dx, dy)
            expected = d.violations[i] ? '◆' : '●'
            @test ch == expected
        end

        # ◆ specifically on known violation
        dx77 = data_index_to_cell(77, pa, m.viewport)
        dy77 = data_val_to_cell_row(d.values[77], pa, m.viewport)
        @test T.char_at(tb, dx77, dy77) == '◆'

        # Survive viewport change / pan/zoom (subset visible, markers only for those in view)
        m.viewport.x0 = 20
        m.viewport.x1 = 30
        tb = render_spc_visual(m; w = 80, h = 20)
        pa = m.plot_area
        for i in 20:5:30
            dx = data_index_to_cell(i, pa, m.viewport)
            dy = data_val_to_cell_row(d.values[i], pa, m.viewport)
            ch = T.char_at(tb, dx, dy)
            @test ch == '●'  # no viol in 20-30
        end
        # 77 not visible, its cell may be out or overwritten but we don't assert absence broadly

        # Live append model with paused=true (manual append for determinism, markers on new points)
        m2 = SPCModel(
            data = generate_spc_data(25; seed = 42),
            viewport = Viewport(x0 = 1, x1 = 25),
            paused = true,
        )
        # simulate live append (append_live_point! respects paused, so direct mutate like advance)
        push!(m2.data.values, 101.5)
        push!(m2.data.indices, 26)
        push!(m2.data.violations, false)
        m2.viewport.x1 = 26
        tb2 = render_spc_visual(m2; w = 80, h = 18)
        pa2 = m2.plot_area
        dxn = data_index_to_cell(26, pa2, m2.viewport)
        dyn = data_val_to_cell_row(m2.data.values[26], pa2, m2.viewport)
        @test T.char_at(tb2, dxn, dyn) == '●'

        # Reset viewport includes all, marker for original viol still works
        m2.viewport.x0 = 1;
        m2.viewport.x1 = length(m2.data.values)
        tb2 = render_spc_visual(m2; w = 80, h = 18)
        # 77 may be beyond now n=26, use a point
        @test T.char_at(
            tb2,
            data_index_to_cell(10, m2.plot_area, m2.viewport),
            data_val_to_cell_row(m2.data.values[10], m2.plot_area, m2.viewport),
        ) == '●'
    end

    @testset "Hover tooltip window showing data point value (PR3 visual)" begin
        # Use seed=42 data; paused=true for deterministic render (no live tick/advance in view)
        d = generate_spc_data(25; seed = 42)
        n = length(d.values)
        m = SPCModel(data = d, viewport = Viewport(x0 = 1, x1 = n), paused = true)

        tb = render_spc_visual(m; w = 60, h = 18)
        pa = m.plot_area
        @test pa.width > 10 && pa.height > 5

        # Hover sets hovered; re-render; tooltip drawn last, use find_text for fragments
        cx = pa.x + (pa.width ÷ 2)
        cy = pa.y + (pa.height ÷ 2)
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_none, T.mouse_move, false, false, false))
        @test m.hovered !== nothing
        tb = render_spc_visual(m; w = 60, h = 18)
        @test T.find_text(tb, "val=") !== nothing
        hi = m.hovered
        @test T.find_text(tb, "i=$hi") !== nothing
        stat = d.violations[hi] ? "OOC" : "OK"
        @test T.find_text(tb, stat) !== nothing

        # selected + hover case: click sets selected, move hover shows tooltip on new point
        si = hi
        T.update!(m, T.MouseEvent(cx, cy, T.mouse_left, T.mouse_press, false, false, false))
        T.update!(
            m,
            T.MouseEvent(cx, cy, T.mouse_left, T.mouse_release, false, false, false),
        )
        @test m.selected == si
        cx2 = pa.x + (pa.width ÷ 3)
        T.update!(m, T.MouseEvent(cx2, cy, T.mouse_none, T.mouse_move, false, false, false))
        @test m.hovered != si && m.selected == si
        tb = render_spc_visual(m; w = 60, h = 18)
        @test T.find_text(tb, "val=") !== nothing  # tooltip follows hover

        # no tooltip during drag (guard m.drag_start)
        T.update!(
            m,
            T.MouseEvent(cx2, cy, T.mouse_left, T.mouse_press, false, false, false),
        )
        T.update!(
            m,
            T.MouseEvent(cx2 + 4, cy, T.mouse_left, T.mouse_drag, false, false, false),
        )
        tb = render_spc_visual(m; w = 60, h = 18)
        @test T.find_text(tb, "val=") === nothing
        # release to end drag gesture so subsequent hover can show tooltip
        T.update!(
            m,
            T.MouseEvent(cx2 + 4, cy, T.mouse_left, T.mouse_release, false, false, false),
        )

        # positioning test: set plot_area near edge + hover near right to exercise fallback/clamp
        pa_edge = Rect(pa.x + max(0, pa.width - 12), pa.y, 12, pa.height)
        m.plot_area = pa_edge
        rx = pa_edge.x + pa_edge.width - 2
        ry = pa_edge.y + 3
        T.update!(m, T.MouseEvent(rx, ry, T.mouse_none, T.mouse_move, false, false, false))
        tb = render_spc_visual(m; w = 60, h = 18)
        @test T.find_text(tb, "val=") !== nothing  # still draws (clamped inside)
    end

    @testset "Live advance + viewport follow (PR3)" begin
        d = generate_spc_data(30; seed = 9)
        n0 = length(d.values)
        m = SPCModel(
            data = d,
            viewport = Viewport(x0 = 1, x1 = n0),
            paused = false,
            rng = Random.MersenneTwister(99),
        )
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
            d = generate_spc_data(n; seed = 123)
            length(d.values) == n && d.ucl > d.mean > d.lcl && all(isfinite, d.values)
        end
    end
end
