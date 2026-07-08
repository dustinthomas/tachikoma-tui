using Test
using Tachikoma
using Supposition, Supposition.Data

const T = Tachikoma

# Include component tests
include("test_hello.jl")
# NOTE: prior to PR1 / execute-plan slice 1, runtests.jl only included test_hello.jl
# (test_spc.jl existed but was not wired here; this additive include ensures
# full-suite gates actually execute new + existing SPC-related tests).
include("test_spc_workbench.jl")
# include("test_my_feature.jl")

# println guarded/removed per review (noise in test output)
