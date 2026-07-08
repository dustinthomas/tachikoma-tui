module TachikomaTUI

# Entry point for Tachikoma.jl TUI projects using the Grok agentic workflow.
using Tachikoma
@tachikoma_app

export Tachikoma

# Include examples / apps
include("hello.jl")
include("spc.jl")
include("spc_workbench.jl")

# Public demo runners
export HelloModel, hello_tachikoma, run_hello

# SPC chart (visual tweaks: click vertical, markers, hover tooltip)
export SPCData, SPCModel, Viewport, generate_spc_data
export static_spc_demo, run_static_spc, spc_demo, run_spc

# SPC Workbench (full reconstruction of all slices on master)
export SPCWorkbenchModel, WorkbenchData, generate_spc_workbench_data
export weco_detect, compute_limits_and_zones, compute_capability
export detect_oos, cpk_band, cpk_color_for_band
export ChartRenderContext, resolve_chart_render_context, point_status
export DEFAULT_WECO_RULES, DEFAULT_CHART_LINES, CHART_LINE_KEYS
export DEFAULT_VISUAL_PREFS, VISUAL_PREF_KEYS
export spc_workbench_demo, run_spc_workbench, spc_workbench, advanced_spc, run_advanced_spc

# Add your own includes here as the project grows:
# include("my_dashboard.jl")
# include("my_app.jl")

end # module
