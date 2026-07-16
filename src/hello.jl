# ═══════════════════════════════════════════════════════════════════════
# Hello Tachikoma — minimal starter TUI
#
# Demonstrates the core Elm-style pattern for Tachikoma.jl apps:
#   @kwdef mutable struct X <: Model
#   should_quit(m)
#   update!(m, KeyEvent)
#   view(m, Frame)
#   app(model)
#
# Keys: [space / +] increment, [r] reset, [q / esc] quit
# ═══════════════════════════════════════════════════════════════════════

using Tachikoma
@tachikoma_app

@kwdef mutable struct HelloModel <: Model
    quit::Bool = false
    count::Int = 0
    tick::Int = 0
end

should_quit(m::HelloModel) = m.quit

function update!(m::HelloModel, evt::KeyEvent)
    if evt.key == :escape || (evt.key == :char && evt.char == 'q')
        m.quit = true
        return
    end

    if evt.key == :char
        if evt.char == ' ' || evt.char == '+'
            m.count += 1
        elseif evt.char == 'r' || evt.char == 'R'
            m.count = 0
        end
    end

    # Support arrow up too
    if evt.key == :up
        m.count += 1
    end
end

function view(m::HelloModel, f::Frame)
    m.tick += 1
    buf = f.buffer
    area = f.area

    # Center content area
    h = area.height
    w = area.width

    # Title
    title = "═══ Tachikoma.jl TUI Starter ═══"
    title_x = max(1, (w - length(title)) ÷ 2 + area.x)
    set_string!(buf, title_x, area.y + 1, title, tstyle(:accent, bold=true))

    # Big count display
    count_str = "Count: $(m.count)"
    count_x = max(1, (w - length(count_str)) ÷ 2 + area.x)
    count_y = area.y + h ÷ 2
    set_string!(buf, count_x, count_y, count_str, tstyle(:primary, bold=true))

    # Instructions
    help = "[space / + / ↑] +1   [r] reset   [q] quit"
    help_x = max(1, (w - length(help)) ÷ 2 + area.x)
    set_string!(buf, help_x, area.y + h - 2, help, tstyle(:text_dim))

    # Subtle footer
    footer = "Tachikoma + Grok agentic workflow"
    set_string!(buf, area.x + 2, area.y + h - 1, footer, tstyle(:text_dim, dim=true))
end

"""
    hello_tachikoma()

Launch the minimal Hello Tachikoma starter app.
"""
function hello_tachikoma()
    app(HelloModel())
end

const run_hello = hello_tachikoma

"""
    record_hello_demo(path="hello_demo.tach"; width=60, height=12, fps=10) -> String

Headless screen capture of the Hello counter using Tachikoma's `record_app`.

Simulates a short scripted session (increment → reset → increment → quit) and
writes a `.tach` recording to `path`. Returns the path written.

This is the trivial documentation / CI recording seed — start here before
workbench captures. Interactive live capture uses **Ctrl+R** in a running app.

# Example

```julia
using TachikomaTUI
record_hello_demo("docs/assets/hello_demo.tach")
```
"""
function record_hello_demo(
    path::AbstractString = "hello_demo.tach";
    width::Int = 60,
    height::Int = 12,
    fps::Int = 10,
)::String
    m = HelloModel()
    # Frame-indexed scripted keys (1-based capture frames after any warmup)
    events = [
        (5, KeyEvent(' ')),   # count → 1
        (10, KeyEvent('+')),  # count → 2
        (15, KeyEvent(:up)),  # count → 3
        (22, KeyEvent('r')),  # reset → 0
        (28, KeyEvent('+')),  # count → 1
        (40, KeyEvent(:escape)),
    ]
    parent = dirname(path)
    if !isempty(parent)
        mkpath(parent)
    end
    record_app(m, String(path); width = width, height = height, frames = 45, fps = fps, events = events)
    return String(path)
end
