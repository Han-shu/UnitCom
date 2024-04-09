using Test
include("NYGrid/build_ny_system.jl")
include("NYGrid/add_ts.jl")
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
model = stochastic_uc(system, Gurobi.Optimizer, start_time = DateTime(2018, 1, 1, 0), scenario_count = 10, horizon = 24)

@testset "stochastic_uc" begin
    @test model[:param].time_steps == 1:24
    @test model[:param].scenarios == 1:10
    @test model[:param].start_time == DateTime(2019, 1, 1, 0)
    @test get_time_series_counts(system) == (3, 0, 3)
    thermal_gen_names = get_name.(get_components(ThermalGen, system))

    fix!(system, model)
    @test is_binary(model[:ug][thermal_gen_names[1],1]) == true
    for g in thermal_gen_names, t in model[:param].time_steps
        unset_binary(model[:ug][g,t])
    end

    @test is_fixed(model[:ug][thermal_gen_names[1],1]) == true
    @test is_binary(model[:ug][thermal_gen_names[1],1]) == false

    optimize!(model)
    @test JuMP.primal_status(model) == MOI.FEASIBLE_POINT
    @test JuMP.dual_status(model) == MOI.FEASIBLE_POINT
    @test isnothing(dual(model[:eq_power_balance][1,1])) == false
end