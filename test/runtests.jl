using Test
using Tachikoma
using Supposition, Supposition.Data

const T = Tachikoma

# Include component tests
include("test_terminal_mouse.jl")
include("test_hello.jl")
# KD24 (PR0): classic SPC chart tests were orphaned; hard-wire into full suite.
# Isolated module: test_spc.jl does `using TachikomaTUI` (imports Viewport / helpers),
# while test_spc_workbench.jl raw-includes src/spc_workbench.jl into Main and defines
# a parallel Viewport when TachikomaTUI is not the host module (KD22 collision).
# Do not remove this module wrapper until pure workbench tests stop raw-including
# src/spc_workbench.jl (flattening into Main re-breaks the suite).
module TestSPCChart
include("test_spc.jl")
end
# SPC workbench (pure WECO via raw include + UI TestBackend)
include("test_spc_workbench.jl")
# Tutorial path recorders (R3–R4) — package load only
include("test_recording_tutorial.jl")
include("test_local_docs.jl")
# include("test_my_feature.jl")

# println guarded/removed per review (noise in test output)
