module TachikomaTUI

# Entry point for Tachikoma.jl TUI projects using the Grok agentic workflow.
using Tachikoma
@tachikoma_app

export Tachikoma

# Include examples / apps
include("hello.jl")

# Public demo runners
export HelloModel, hello_tachikoma, run_hello

# Add your own includes here as the project grows:
# include("my_dashboard.jl")
# include("my_app.jl")

end # module
