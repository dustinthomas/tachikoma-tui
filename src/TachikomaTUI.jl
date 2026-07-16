module TachikomaTUI

# Entry point for Tachikoma.jl TUI projects using the Grok agentic workflow.
using Tachikoma
@tachikoma_app

export Tachikoma

# Include examples / apps
include("hello.jl")
include("spc.jl")
include("spc_workbench.jl")
include("spc_workbench_io.jl")  # PR3 CSV + PR4 JSON (after workbench types)
include("local_docs.jl")        # open Documenter HTML in system browser

# Public demo runners
export HelloModel, hello_tachikoma, run_hello, record_hello_demo

# SPC chart (visual tweaks: click vertical, markers, hover tooltip)
export SPCData, SPCModel, Viewport, generate_spc_data
export static_spc_demo, run_static_spc, spc_demo, run_spc

# SPC Workbench (full reconstruction of all slices on master)
export SPCWorkbenchModel, WorkbenchData, generate_spc_workbench_data
export weco_detect, weco_rules_at_index, weco_explain_content
export WECO_RULE_DESCS, WECO_EXPLAIN_HOW, WECO_POPUP_MAX_BODY
export compute_limits_and_zones, compute_capability
export detect_oos, cpk_band, cpk_color_for_band
export compute_fit_y_range, y_extras_from_limits, fit_viewport_y!, auto_fit_viewport_y!
export ChartRenderContext, resolve_chart_render_context, point_status, auto_limits
export SecondarySeries, secondary_series_for, empty_secondary_series
export SS_FACTORS, subgroup_means_and_ranges, subgroup_means_and_s
export DEFAULT_WECO_RULES, DEFAULT_CHART_LINES, CHART_LINE_KEYS
export LINE_STYLE_KEYS, LINE_STYLE_LABELS, DEFAULT_CHART_LINE_STYLES
export DEFAULT_VISUAL_PREFS, VISUAL_PREF_KEYS
export GraphPreset, FileBrowserEntry, capture_graph_preset, apply_graph_preset!
export save_named_graph_preset!, apply_named_graph_preset!
export is_attribute_chart
export ChartType, ChartSpec, empty_workbench_data, CHART_TYPE_WIRE, parse_chart_type, chart_type_to_string
export I_MR, Xbar_R, Xbar_S, p_chart, np_chart, c_chart, u_chart
export SharedTable, mean_or_0, std_or_0, compute_chart_series, materialize_chart_from_table!
export shared_table_from_columns_rows, fill_shared_table!
export ToolEntry, ParamEntry, select_param!, add_param_chart!, add_analysis_chart!
export add_chart!, clone_chart!, delete_chart!, rename_chart!, set_active_chart!
export visible_charts, dashboard_pane_charts, dashboard_display_set, effective_dashboard_max_panes
export toggle_dashboard_scope!, toggle_compare_pin!
export default_fake_tools, default_fake_tool_params, build_fake_tool_table, materialize_param_chart!
export workbench_to_dict, workbench_from_dict, workbench_from_dict!
export export_csv_series, chart_for_export
export save_workbench, load_workbench, load_workbench!
export graph_preset_to_dict, graph_preset_from_dict, save_graph_preset, load_graph_preset
export list_browser_entries
export GraphConfigIndexEntry, GRAPH_CONFIG_INDEX_CAP
export default_graph_config_index_path
export read_graph_config_index, write_graph_config_index
export upsert_graph_config_index_entry!, graph_preset_index_summary
export graph_config_index_entry_from_preset, remove_graph_config_index_entry!
export extract_html_spc_state, extract_html_spc_state_file
export html_state_to_workbench, html_state_to_workbench!
export load_html_archive, load_html_archive!
export spc_workbench_demo, run_spc_workbench, spc_workbench, advanced_spc, run_advanced_spc
export make_spc_workbench_model, make_blank_workbench, make_pecvd_tutorial_workbench
export default_pecvd_fixture_dir
export record_blank_workbench_demo, record_pecvd_tutorial_demo
export add_tool!, delete_tool!
export package_root, local_docs_build_dir, resolve_local_docs_file, file_url
export open_in_browser, open_local_docs, LOCAL_DOCS_PAGES

# SPC Workbench I/O (PR3 CSV import)
export CsvParseOk, CsvParseErr, parse_csv_table
export import_csv_into_chart!, import_csv_new_chart!, import_csv_into_model!

# Add your own includes here as the project grows:
# include("my_dashboard.jl")
# include("my_app.jl")

end # module
