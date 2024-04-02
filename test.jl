using Test
include("src/stochastic_uc.jl")
include("system/case5_re.jl")
model = stochastic_uc(system, Gurobi.Optimizer, start_time = DateTime(2018, 1, 1, 0), scenario_count = 10, horizon = 24)

@testset "stochastic_uc" begin
    @test model[:param].time_steps == 1:24
    @test model[:param].scenarios == 1:10
    @test model[:param].start_time == DateTime(2018, 1, 1, 0)
    @test get_time_series_counts(system) == (5, 0, 5)
end