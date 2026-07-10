# API Reference

Public API of `TachikomaTUI`. Prefer package load:

```julia
using TachikomaTUI
```

I/O helpers (`workbench_to_dict`, `save_workbench`, `load_workbench`, …) must
be exercised via the package module — do not raw-include `spc_workbench_io.jl`
into a process that also loads `TachikomaTUI`.

```@meta
CurrentModule = TachikomaTUI
```

## Named groups (exports)

| Group | Symbols |
|-------|---------|
| Runners | `hello_tachikoma`, `static_spc_demo`, `spc_demo`, `spc_workbench_demo`, `spc_workbench` |
| Workbench model | `SPCWorkbenchModel`, `WorkbenchData`, `ChartSpec`, `ChartType`, `ToolEntry` |
| Chart library | `add_chart!`, `clone_chart!`, `delete_chart!`, `rename_chart!`, `set_active_chart!` |
| JSON I/O v1 | `workbench_to_dict`, `workbench_from_dict`, `workbench_from_dict!`, `save_workbench`, `load_workbench`, `load_workbench!` |
| WECO / limits | `weco_detect`, `compute_limits_and_zones`, `compute_capability`, `resolve_chart_render_context`, `detect_oos`, `cpk_band` |
| Viewport | `fit_viewport_y!`, `auto_fit_viewport_y!`, `compute_fit_y_range`, `Viewport` |
| Classic SPC | `SPCModel`, `SPCData`, `generate_spc_data` |

See [SPC Workbench](@ref) for keys, CSV format, and JSON schema contracts.

## Public docs (autodocs)

Documented public names (those with Julia docstrings) are listed below.
Undocumented reexports are intentionally omitted here; see the export list in
`src/TachikomaTUI.jl`.

```@autodocs
Modules = [TachikomaTUI]
Private = false
Order = [:type, :function, :constant, :macro]
```
