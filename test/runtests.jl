using Test
using Tachikoma
using Supposition, Supposition.Data

const T = Tachikoma

# Include component tests
include("test_hello.jl")
# include("test_my_feature.jl")

# println guarded/removed per review (noise in test output)
