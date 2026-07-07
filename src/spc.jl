# ═══════════════════════════════════════════════════════════════════════
# SPC Interactive — Statistical Process Control chart demo for Tachikoma.jl
#
# Full implementation per design: seeded data, Canvas render (data, dashed limits,
# violations, crosshair), Mouse hover/drag-pan/wheel-zoom, live append, arc gauges,
# side panel, StatusBar footer.
#
# Keys: q/esc quit, p pause, r/z reset viewport, arrows pan
# Mouse: hover for details + crosshair, click for persistent ┃ vertical (selected), left-drag pan, wheel zoom
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma
@tachikoma_app

using Random
using Statistics: mean, std

# ── Data model ─────────────────────────────────────────────────────────

struct SPCData
    values::Vector{Float64}
    indices::Vector{Int}
    mean::Float64
    sd::Float64
    ucl::Float64
    lcl::Float64
    violations::Vector{Bool}
end

@kwdef mutable struct Viewport
    x0::Int = 1
    x1::Int = 1
    ylo::Float64 = 0.0
    yhi::Float64 = 1.0
end

@kwdef mutable struct SPCModel <: Model
    quit::Bool = false
    tick::Int = 0
    data::SPCData
    viewport::Viewport = Viewport()
    hovered::Union{Nothing, Int} = nothing
    selected::Union{Nothing, Int} = nothing
    paused::Bool = false
    plot_area::Rect = Rect(0,0,0,0)
    side_area::Rect = Rect(0,0,0,0)
    drag_start::Union{Nothing, NamedTuple{(:x,:y,:vp), Tuple{Int,Int,Viewport}}} = nothing
    last_event::String = ""
    live_max::Int = 200
    rng::MersenneTwister = Random.MersenneTwister(1234)
    current_gauge_val::Float64 = 0.0
end

should_quit(m::SPCModel) = m.quit

# ── Seeded generator (PR1 static data) ─────────────────────────────────

function generate_spc_data(n::Int=80; seed::Int=42, μ::Float64=100.0, σ::Float64=2.5, ooc_prob::Float64=0.07)
    rng = Random.MersenneTwister(seed)
    vals = Float64[]
    for i in 1:n
        v = μ + σ * randn(rng)
        if rand(rng) < ooc_prob
            v += (rand(rng) < 0.5 ? 3.8 : -3.5) * σ
        end
        if 30 < i < 45
            v += 1.8 * σ
        end
        push!(vals, v)
    end
    μ̂ = mean(vals)
    σ̂ = std(vals; corrected=true)
    ucl = μ̂ + 3 * σ̂
    lcl = μ̂ - 3 * σ̂
    viols = [abs(v - μ̂) > 3 * σ̂ for v in vals]
    SPCData(vals, collect(1:n), μ̂, σ̂, ucl, lcl, viols)
end

# Live advance (PR3+; stub for PR1 static/paused)
function advance_live!(m::SPCModel)
    m.paused && return
    n = length(m.data.values)
    n >= m.live_max && return
    last = m.data.values[end]
    nextv = 0.6 * last + 0.4 * m.data.mean + m.data.sd * 0.8 * randn(m.rng)
    if rand(m.rng) < 0.04
        nextv += 3.2 * m.data.sd
    end
    push!(m.data.values, nextv)
    push!(m.data.indices, n + 1)
    push!(m.data.violations, abs(nextv - m.data.mean) > 3 * m.data.sd)
    # viewport follow handled in view for auto-scroll
end

append_live_point!(m::SPCModel) = advance_live!(m)

# ── Viewport helpers (PR1 uses full data; pan/zoom in PR2) ─────────────

const MIN_X_SPAN = 5
const MIN_Y_SPAN = 0.1

function clamp_viewport!(vp::Viewport, data_n::Int)
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
    vp
end

# PR2: pan and zoom (used by MouseEvent)
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

# Cell to data index (for hover/click)
function cell_to_data_index(cell_x::Int, pa::Rect, vp::Viewport)
    pa.width <= 1 && return vp.x0
    frac = clamp((cell_x - pa.x) / (pa.width - 1), 0.0, 1.0)
    idx = vp.x0 + round(Int, frac * (vp.x1 - vp.x0))
    clamp(idx, vp.x0, vp.x1)
end

# Nearest point hover (use frac for index, find closest visible point)
function compute_hovered_index(evt_x::Int, evt_y::Int, pa::Rect, d::SPCData, vp::Viewport)::Union{Nothing,Int}
    !contains(pa, evt_x, evt_y) && return nothing
    if vp.x1 == vp.x0
        return vp.x0
    end
    frac_x = clamp( (evt_x - pa.x) / (pa.width - 1) , 0.0, 1.0)
    target_idx = vp.x0 + frac_x * (vp.x1 - vp.x0)
    best_i = vp.x0
    best_d = Inf
    for i in vp.x0:vp.x1
        (i < 1 || i > length(d.values)) && continue
        dd = abs(i - target_idx)
        if dd < best_d
            best_d = dd
            best_i = i
        end
    end
    best_i
end

# Reverse for crosshair
function data_index_to_cell(i::Int, pa::Rect, vp::Viewport)
    if pa.width <= 1 || vp.x1 == vp.x0
        return pa.x
    end
    frac = (i - vp.x0) / (vp.x1 - vp.x0)
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

# ── Coordinate mapping (render path) ───────────────────────────────────

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
    round(Int, (dot_h - 1) - t * (dot_h - 1))  # flip Y
end

# ── Dashed line helper (Bresenham variant) ─────────────────────────────

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

# ── Update (KeyEvent only for PR1) ─────────────────────────────────────

function update!(m::SPCModel, evt::KeyEvent)
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
            # reset viewport to full data
            n = length(m.data.values)
            m.viewport.x0 = 1
            m.viewport.x1 = n
            m.viewport.ylo = minimum(m.data.values) - 1.0
            m.viewport.yhi = maximum(m.data.values) + 1.0
            clamp_viewport!(m.viewport, n)
            m.hovered = nothing
            m.selected = nothing
            m.drag_start = nothing
            m.last_event = "reset"
        end
    end

    # simple pan with arrows (even on static for PR1)
    if evt.key == :left
        n = length(m.data.values)
        m.viewport.x0 = max(1, m.viewport.x0 - 2)
        m.viewport.x1 = max(m.viewport.x0 + MIN_X_SPAN - 1, m.viewport.x1 - 2)
        clamp_viewport!(m.viewport, n)
    elseif evt.key == :right
        n = length(m.data.values)
        m.viewport.x1 = min(n, m.viewport.x1 + 2)
        m.viewport.x0 = min(m.viewport.x0 + 2, m.viewport.x1 - MIN_X_SPAN + 1)
        clamp_viewport!(m.viewport, n)
    end
end

# PR2: Mouse interactions (hover, drag pan, wheel zoom)
function update!(m::SPCModel, evt::MouseEvent)
    m.last_event = string(evt.action, " ", evt.button)
    pa = m.plot_area
    if !contains(pa, evt.x, evt.y)
        if evt.action == mouse_release
            m.drag_start = nothing
        end
        return
    end

    n = length(m.data.values)

    if evt.button == mouse_scroll_up || evt.button == mouse_scroll_down
        factor = (evt.button == mouse_scroll_up) ? 0.75 : 1.33
        cx = cell_to_data_index(evt.x, pa, m.viewport)
        zoom_viewport_around!(m.viewport, cx, factor, n)
        return
    end

    if evt.action == mouse_press && evt.button == mouse_left
        m.drag_start = (x=evt.x, y=evt.y, vp=deepcopy(m.viewport))
        m.hovered = compute_hovered_index(evt.x, evt.y, pa, m.data, m.viewport)
        m.selected = m.hovered  # persistent ┃ vertical (distinct from transient hover)
        return
    end

    if evt.action == mouse_drag && m.drag_start !== nothing && evt.button == mouse_left
        dx = evt.x - m.drag_start.x
        pan_viewport!(m.viewport, -dx, pa.width, n)  # sign for natural drag
        m.drag_start = (x=evt.x, y=evt.y, vp=deepcopy(m.viewport))  # update for continued drag
        return
    end

    if evt.action == mouse_release
        m.drag_start = nothing
        return
    end

    if evt.action == mouse_move || evt.action == mouse_press
        m.hovered = compute_hovered_index(evt.x, evt.y, pa, m.data, m.viewport)
    end
end

# ── View (static render for PR1) ───────────────────────────────────────

function view(m::SPCModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    # Live update (PR3+): tick-driven append using seeded RNG (deterministic).
    # For static use static_spc_demo() (paused=true).
    if !m.paused && (m.tick % 4 == 0)
        advance_live!(m)
        # auto-follow viewport when live and at the end (refinement)
        cur_n = length(m.data.values)
        if m.viewport.x1 >= cur_n - 1
            m.viewport.x1 = cur_n
            # keep a reasonable window from the left if needed
            if m.viewport.x1 - m.viewport.x0 > 80
                m.viewport.x0 = m.viewport.x1 - 60
            end
            clamp_viewport!(m.viewport, cur_n)
        end
    end

    if area.width < 20 || area.height < 6
        set_string!(buf, area.x, area.y, "SPC (small terminal)", tstyle(:text_dim))
        return
    end

    # Layout
    rows = split_layout(Layout(Vertical, [Fixed(1), Fill(), Fixed(3), Fixed(1)]), area)
    length(rows) < 4 && return
    header = rows[1]
    main = rows[2]
    gauge_row = rows[3]
    footer = rows[4]

    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(28)]), main)
    length(cols) < 2 && return
    plot_rect = cols[1]
    side_rect = cols[2]

    # Header
    set_string!(buf, header.x + 1, header.y,
        "SPC Chart (seed=42)  [p]pause [r/z]reset [←→]pan wheel=zoom [q]quit",
        tstyle(:title, bold=true))

    # Plot block + canvas
    plot_block = Block(
        title = "Process Data (mouse: hover/click/drag/wheel)",
        border_style = tstyle(:border),
        title_style = tstyle(:title)
    )
    plot_inner = render(plot_block, plot_rect, buf)
    m.plot_area = plot_inner

    cw = plot_inner.width
    ch = plot_inner.height

    if cw > 0 && ch > 0
        has_viol = any(m.data.violations[m.viewport.x0:m.viewport.x1])
        c = create_canvas(cw, ch; style = has_viol ? tstyle(:accent) : tstyle(:primary))
        dw, dh = canvas_dot_size(c)

        # Data line (visible slice)
        prev_dx = prev_dy = nothing
        for i in m.viewport.x0:m.viewport.x1
            v = m.data.values[i]
            dx = map_to_dot_x(i, m.viewport, dw)
            dy = map_to_dot_y(v, m.viewport, dh)
            set_point!(c, dx, dy)
            if prev_dx !== nothing
                line!(c, prev_dx, prev_dy, dx, dy)
            end
            prev_dx, prev_dy = dx, dy
        end

        # Limits (dashed)
        ucl_y = map_to_dot_y(m.data.ucl, m.viewport, dh)
        lcl_y = map_to_dot_y(m.data.lcl, m.viewport, dh)
        mean_y = map_to_dot_y(m.data.mean, m.viewport, dh)
        dashed_line!(c, 0, ucl_y, dw - 1, ucl_y; dash = 4)
        dashed_line!(c, 0, lcl_y, dw - 1, lcl_y; dash = 4)
        line!(c, 0, mean_y, dw - 1, mean_y)

        # Violation markers (ticks)
        for i in m.viewport.x0:m.viewport.x1
            if m.data.violations[i]
                dx = map_to_dot_x(i, m.viewport, dw)
                dy = map_to_dot_y(m.data.values[i], m.viewport, dh)
                set_point!(c, dx, max(0, dy - 1))
                set_point!(c, dx, dy + 1)
            end
        end

        render_canvas(c, plot_inner, f)

        # Post-render overlay for selected (PR1): full-height ┃ vertical at click point.
        # Uses data_index_to_cell (from viewport slice) so survives pan/zoom/live append.
        # Drawn before crosshair (hover crosshair unchanged). Marker at data row wins later PRs.
        # Note: if selected==hovered immediately after press, crosshair may overwrite top (y+1) with '│' (see below); test decouples via move.
        if (si = m.selected) !== nothing && si >= m.viewport.x0 && si <= m.viewport.x1
            sx = data_index_to_cell(si, plot_inner, m.viewport)
            for y in (plot_inner.y + 1):(bottom(plot_inner) - 1)
                set_char!(buf, sx, y, '┃', tstyle(:secondary, bold=true))
            end
        end

        # Crosshair + marker from hovered (PR2)
        if (hi = m.hovered) !== nothing && hi >= m.viewport.x0 && hi <= m.viewport.x1
            hx = data_index_to_cell(hi, plot_inner, m.viewport)
            hy = data_val_to_cell_row(m.data.values[hi], plot_inner, m.viewport)
            set_char!(buf, hx, plot_inner.y + 1, '│', tstyle(:accent))
            set_char!(buf, plot_inner.x + 1, hy, '─', tstyle(:accent))
            set_char!(buf, hx, hy, '●', tstyle(:accent, bold=true))
        end

        # Axis labels (minimal)
        set_string!(buf, plot_inner.x, plot_inner.y + ch - 1, string(m.viewport.x0), tstyle(:text_dim))
        set_string!(buf, right(plot_inner) - 3, plot_inner.y + ch - 1, string(m.viewport.x1), tstyle(:text_dim))
    end

    # Side panel
    side_block = Block(title="Details", border_style=tstyle(:border))
    side_inner = render(side_block, side_rect, buf)
    m.side_area = side_inner
    x = side_inner.x
    y = side_inner.y
    set_string!(buf, x, y, "n=$(length(m.data.values)) live", tstyle(:text)); y += 1
    set_string!(buf, x, y, "μ=$(round(m.data.mean;digits=2)) σ=$(round(m.data.sd;digits=2))", tstyle(:text_dim)); y += 1
    set_string!(buf, x, y, "UCL=$(round(m.data.ucl;digits=1)) LCL=$(round(m.data.lcl;digits=1))", tstyle(:text_dim)); y += 2
    if (hi = m.hovered) !== nothing && hi >= m.viewport.x0 && hi <= m.viewport.x1
        v = m.data.values[hi]; stat = m.data.violations[hi] ? "OOC ✗" : "OK"
        set_string!(buf, x, y, "hovered[$hi]=$(round(v;digits=2)) $stat", tstyle(:accent, bold=true)); y += 1
    else
        set_string!(buf, x, y, "hover over points", tstyle(:text_dim)); y += 1
    end
    y += 1
    # legend
    set_char!(buf, x, y, '■', tstyle(:primary))
    set_string!(buf, x+1, y, " data  ", tstyle(:text_dim)); y += 1
    set_string!(buf, x, y, " - - UCL/LCL", tstyle(:text_dim)); y += 2
    # controls
    set_string!(buf, x, y, "keys: p pause, r/z reset, arrows pan", tstyle(:text_dim))

    # Gauges row (PR3 refinement: arc + needle using canvas primitives)
    gcols = split_layout(Layout(Horizontal, [Fill(), Fill()]), gauge_row)
    length(gcols) < 2 && return
    # Gauge 1: current value (arc scale + needle)
    g1 = gcols[1]
    g1i = render(Block(border_style=tstyle(:border)), g1, buf)  # get inner-ish area
    if g1i.width > 4 && g1i.height > 3
        gc = create_canvas(max(1, g1i.width), max(1, g1i.height); style = tstyle(:primary))
        cx, cy = g1i.width ÷ 2, g1i.height - 1
        r = min(g1i.width, g1i.height) ÷ 2 - 1
        arc!(gc, cx, cy, r, 0.0, 180.0)
        # needle based on current (last) value normalized to limits
        lastv = m.data.values[end]
        norm = clamp( (lastv - m.data.lcl) / (m.data.ucl - m.data.lcl + 1e-9), 0.0, 1.0 )
        ang = deg2rad(180 - norm * 180)
        nx = round(Int, cx + r * 0.8 * cos(ang))
        ny = round(Int, cy - r * 0.8 * sin(ang))
        line!(gc, cx, cy, nx, ny)
        set_point!(gc, cx, cy)
        render_canvas(gc, g1i, f)
    end
    set_string!(buf, g1.x + 1, g1.y, "Current", tstyle(:text_dim))

    # Gauge 2: simple violation indicator or % in control
    g2 = gcols[2]
    g2i = render(Block(border_style=tstyle(:border)), g2, buf)
    viol_count = count(m.data.violations[max(1, end-20):end])
    pct = 100 - round(viol_count / min(20, length(m.data.violations)) * 100)
    if g2i.width > 4 && g2i.height > 2
        set_string!(buf, g2i.x + 1, g2i.y, "InCtrl ~$(round(Int, pct))%", tstyle(:text_dim))
    end

    # Footer using StatusBar (PR3 refinement)
    render(StatusBar(
        left = [Span(" paused=$(m.paused)  last=$(m.last_event) ", tstyle(:text_dim))],
        right = [Span("[q]quit ", tstyle(:text_dim))]
    ), footer, buf)
end

# ── Runners ────────────────────────────────────────────────────────────

"""
    static_spc_demo()

PR1 static demo. Full data viewport, no live mutation inside view.
Use this for initial gates and TestBackend tests.
"""
function static_spc_demo()
    data = generate_spc_data(80; seed=42)
    n = length(data.values)
    vp = Viewport(x0=1, x1=n,
                  ylo=minimum(data.values)-1.0,
                  yhi=maximum(data.values)+1.0)
    m = SPCModel(data=data, viewport=vp, paused=true)
    clamp_viewport!(m.viewport, n)
    app(m)
end

const run_static_spc = static_spc_demo

"""
    spc_demo(; paused=false)

Main entry. For PR1 use paused=true (static).
"""
function spc_demo(; paused::Bool = false)
    data = generate_spc_data(80; seed=42)
    n = length(data.values)
    vp = Viewport(x0=1, x1=n,
                  ylo=minimum(data.values)-1.0,
                  yhi=maximum(data.values)+1.0)
    m = SPCModel(data=data, viewport=vp, paused=paused)
    clamp_viewport!(m.viewport, n)
    app(m)
end

const run_spc = spc_demo
