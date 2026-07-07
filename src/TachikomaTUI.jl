module TachikomaTUI

# Entry point for Tachikoma.jl TUI projects using the Grok agentic workflow.
using Tachikoma
@tachikoma_app

export Tachikoma

# Include examples / apps
include("hello.jl")
include("spc.jl")

# Public demo runners
export HelloModel, hello_tachikoma, run_hello

# SPC chart (visual tweaks: click vertical, markers, hover tooltip)
export SPCData, SPCModel, Viewport, generate_spc_data
export static_spc_demo, run_static_spc, spc_demo, run_spc

# Add your own includes here as the project grows:
# include("my_dashboard.jl")
# include("my_app.jl")

end # module
