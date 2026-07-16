# ═══════════════════════════════════════════════════════════════════════
# Terminal mouse enable — cross-platform (Windows + Linux/macOS)
#
# Tachikoma 2.x enables only CSI ?1000/1002/1006 (clicks + button-drag + SGR).
# That omits ?1003 (any-event tracking), so free mouse-move / hover never
# arrives — hover vertical line and move-driven tooltips stay dead on every OS.
#
# On Windows, console Quick Edit mode also steals left-clicks for text
# selection unless cleared while the TUI runs (classic conhost / ConPTY).
#
# Call enable_app_mouse! from init!(model, terminal) and disable_app_mouse!
# from cleanup! (or when leaving the TUI) so both platforms get full SGR
# mouse + a clean restore.
# ═══════════════════════════════════════════════════════════════════════

"""CSI mouse on: basic + button-event + any-event (hover) + SGR encoding."""
const APP_MOUSE_ON =
    "\e[?1000h" *  # clicks
    "\e[?1002h" *  # drag while button held
    "\e[?1003h" *  # all motion (hover / mouse_move) — missing from Tachikoma MOUSE_ON
    "\e[?1006h"    # SGR mouse reporting

"""CSI mouse off — must include 1003l if we turned 1003 on."""
const APP_MOUSE_OFF =
    "\e[?1000l" *
    "\e[?1002l" *
    "\e[?1003l" *
    "\e[?1006l"

# Windows console mode bits (Win32 console API)
const _WIN_STD_INPUT_HANDLE = UInt32(0xFFFFFFF6)  # (DWORD)-10
const _WIN_ENABLE_QUICK_EDIT_MODE = UInt32(0x0040)
const _WIN_ENABLE_EXTENDED_FLAGS = UInt32(0x0080)
const _WIN_ENABLE_VIRTUAL_TERMINAL_INPUT = UInt32(0x0200)
const _WIN_ENABLE_MOUSE_INPUT = UInt32(0x0010)

"""Saved Win32 console input mode for restore in disable_app_mouse!."""
const _WIN_SAVED_CONSOLE_MODE = Ref{Union{Nothing,UInt32}}(nothing)

"""True when `seq` enables full app mouse modes (1000+1002+1003+1006)."""
function mouse_seq_is_full_tracking(seq::AbstractString)::Bool
    return occursin("1000h", seq) &&
           occursin("1002h", seq) &&
           occursin("1003h", seq) &&
           occursin("1006h", seq)
end

"""True when `seq` disables full app mouse modes (matching offs)."""
function mouse_seq_is_full_off(seq::AbstractString)::Bool
    return occursin("1000l", seq) &&
           occursin("1002l", seq) &&
           occursin("1003l", seq) &&
           occursin("1006l", seq)
end

"""
    _windows_console_prepare_mouse!() -> Union{Nothing,UInt32}

On Windows: disable Quick Edit (so clicks are not stolen for selection),
ensure extended flags + virtual terminal input. Returns previous mode for
restore, or `nothing` on non-Windows / failure.
"""
function _windows_console_prepare_mouse!()
    Sys.iswindows() || return nothing
    try
        h = ccall((:GetStdHandle, "kernel32"), Ptr{Cvoid}, (UInt32,), _WIN_STD_INPUT_HANDLE)
        h == C_NULL && return nothing
        h == Ptr{Cvoid}(-1 % UInt) && return nothing
        mode = Ref{UInt32}(0)
        ok = ccall((:GetConsoleMode, "kernel32"), Int32, (Ptr{Cvoid}, Ptr{UInt32}), h, mode)
        ok == 0 && return nothing
        saved = mode[]
        # Quick Edit steals clicks; VT input required for CSI mouse on modern hosts.
        newmode = (saved | _WIN_ENABLE_EXTENDED_FLAGS | _WIN_ENABLE_VIRTUAL_TERMINAL_INPUT) &
                  ~_WIN_ENABLE_QUICK_EDIT_MODE
        # Prefer not forcing legacy ENABLE_MOUSE_INPUT — VT SGR path is what
        # Tachikoma's parser understands (ESC [ < … M/m).
        ccall((:SetConsoleMode, "kernel32"), Int32, (Ptr{Cvoid}, UInt32), h, newmode)
        return saved
    catch
        return nothing
    end
end

"""Restore console input mode saved by `_windows_console_prepare_mouse!`."""
function _windows_console_restore_mouse!(saved::Union{Nothing,UInt32})
    saved === nothing && return nothing
    Sys.iswindows() || return nothing
    try
        h = ccall((:GetStdHandle, "kernel32"), Ptr{Cvoid}, (UInt32,), _WIN_STD_INPUT_HANDLE)
        h == C_NULL && return nothing
        h == Ptr{Cvoid}(-1 % UInt) && return nothing
        ccall((:SetConsoleMode, "kernel32"), Int32, (Ptr{Cvoid}, UInt32), h, saved)
    catch
    end
    return nothing
end

"""
    enable_app_mouse!(io::IO)

Write full mouse-tracking CSI to `io` and apply Windows console prep when needed.
Safe on Linux/macOS (CSI only; console API is a no-op).
"""
function enable_app_mouse!(io::IO)
    if Sys.iswindows()
        saved = _windows_console_prepare_mouse!()
        if saved !== nothing && _WIN_SAVED_CONSOLE_MODE[] === nothing
            _WIN_SAVED_CONSOLE_MODE[] = saved
        end
    end
    try
        print(io, APP_MOUSE_ON)
        flush(io)
    catch
        # Headless / closed pipe — ignore
    end
    return nothing
end

"""
    enable_app_mouse!(t::Terminal)

Enable full mouse tracking on a Tachikoma `Terminal` (sets `mouse_enabled`).
"""
function enable_app_mouse!(t::Terminal)
    t.mouse_enabled = true
    enable_app_mouse!(t.io)
    return nothing
end

"""
    disable_app_mouse!(io::IO = stdout)

Turn off full mouse tracking (including 1003) and restore Windows console mode.
"""
function disable_app_mouse!(io::IO = stdout)
    try
        print(io, APP_MOUSE_OFF)
        flush(io)
    catch
    end
    if Sys.iswindows()
        saved = _WIN_SAVED_CONSOLE_MODE[]
        _windows_console_restore_mouse!(saved)
        _WIN_SAVED_CONSOLE_MODE[] = nothing
    end
    return nothing
end

"""
    disable_app_mouse!(t::Terminal)

Disable mouse on a Tachikoma terminal and restore host console mode.
"""
function disable_app_mouse!(t::Terminal)
    t.mouse_enabled = false
    disable_app_mouse!(t.io)
    return nothing
end

"""
    ensure_app_mouse!(t::Terminal)

Idempotent re-assert of full mouse modes (use after init or if Ctrl+G toggled
back on with Tachikoma's shorter MOUSE_ON sequence).
"""
function ensure_app_mouse!(t::Terminal)
    t.mouse_enabled || return nothing
    enable_app_mouse!(t)
    return nothing
end

# Active terminal for optional periodic re-assert (Ctrl+G re-enable uses stock
# MOUSE_ON without 1003; we refresh full modes while the app holds the TTY).
const _ACTIVE_MOUSE_TERM = Ref{Union{Nothing,Terminal}}(nothing)
const _MOUSE_REASSERT_EVERY = 90  # frames ≈ 1.5s at 60fps

"""Remember the live Terminal for re-assert / cleanup (called from init!)."""
function bind_app_mouse_terminal!(t::Terminal)
    _ACTIVE_MOUSE_TERM[] = t
    return nothing
end

"""Clear the live Terminal binding (called from cleanup!)."""
function unbind_app_mouse_terminal!()
    _ACTIVE_MOUSE_TERM[] = nothing
    return nothing
end

"""
    maybe_reassert_app_mouse!(tick::Int)

On a schedule, re-send full mouse CSI while Tachikoma still has mouse enabled.
No-ops when unbound, mouse toggled off (Ctrl+G), or between schedule ticks.
"""
function maybe_reassert_app_mouse!(tick::Int)
    t = _ACTIVE_MOUSE_TERM[]
    t === nothing && return nothing
    t.mouse_enabled || return nothing
    tick > 0 && (tick % _MOUSE_REASSERT_EVERY == 0) || return nothing
    # Re-print CSI only (skip re-reading Win32 mode every pulse)
    try
        print(t.io, APP_MOUSE_ON)
        flush(t.io)
    catch
    end
    return nothing
end
