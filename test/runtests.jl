using Test
using Tachikoma
using Supposition, Supposition.Data

const T = Tachikoma

# Include component tests
include("test_hello.jl")
# KD24 (PR0): classic SPC chart tests were orphaned; hard-wire into full suite.
# Isolated module: test_spc.jl does `using TachikomaTUI` (imports Viewport / helpers),
# while test_spc_workbench.jl raw-includes src/spc_workbench.jl into Main and defines
# a parallel Viewport when TachikomaTUI is not the host module (KD22 collision).
module TestSPCChart
include("test_spc.jl")
end
# SPC workbench (pure WECO via raw include + UI TestBackend)
include("test_spc_workbench.jl")
# include("test_my_feature.jl")

# println guarded/removed per review (noise in test output)
