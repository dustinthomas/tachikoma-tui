module TachikomaTUI

# Entry point for Tachikoma.jl TUI projects using the Grok agentic workflow.
using Tachikoma
@tachikoma_app

export Tachikoma

# Include examples / apps
include("hello.jl")
include("spc.jl")
include("spc_workbench.jl")
include("spc_workbench_io.jl")  # PR3: CSV import (after workbench types)

# Public demo runners
export HelloModel, hello_tachikoma, run_hello

# SPC chart (visual tweaks: click vertical, markers, hover tooltip)
export SPCData, SPCModel, Viewport, generate_spc_data
export static_spc_demo, run_static_spc, spc_demo, run_spc

# SPC Workbench (full reconstruction of all slices on master)
export SPCWorkbenchModel, WorkbenchData, generate_spc_workbench_data
export weco_detect, compute_limits_and_zones, compute_capability
export detect_oos, cpk_band, cpk_color_for_band
export compute_fit_y_range, y_extras_from_limits, fit_viewport_y!, auto_fit_viewport_y!
export ChartRenderContext, resolve_chart_render_context, point_status, auto_limits
export SS_FACTORS, subgroup_means_and_ranges, subgroup_means_and_s
export DEFAULT_WECO_RULES, DEFAULT_CHART_LINES, CHART_LINE_KEYS
export DEFAULT_VISUAL_PREFS, VISUAL_PREF_KEYS
export ChartType, ChartSpec, empty_workbench_data, CHART_TYPE_WIRE, parse_chart_type, chart_type_to_string
export I_MR, Xbar_R, Xbar_S, p_chart, np_chart, c_chart, u_chart
export ToolEntry, add_chart!, clone_chart!, delete_chart!, rename_chart!, set_active_chart!
export visible_charts, dashboard_pane_charts
export spc_workbench_demo, run_spc_workbench, spc_workbench, advanced_spc, run_advanced_spc

# SPC Workbench I/O (PR3 CSV import)
export CsvParseOk, CsvParseErr, parse_csv_table
export import_csv_into_chart!, import_csv_new_chart!, import_csv_into_model!

# Add your own includes here as the project grows:
# include("my_dashboard.jl")
# include("my_app.jl")

end # module
