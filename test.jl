using Test
include("NYGrid/build_ny_system.jl")
include("NYGrid/add_ts.jl")
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
model = stochastic_uc(system, Gurobi.Optimizer, start_time = DateTime(2019, 1, 1, 0), scenario_count = 10, horizon = 48)
optimize!(model)
fix!(system, model)
thermal_gen_names = get_name.(get_components(ThermalGen, system))
for g in thermal_gen_names, t in model[:param].time_steps
    unset_binary(model[:ug][g,t])
end 
optimize!(model)

LMP = dual(model[:eq_power_balance][1,48])
wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)
wind_gen_names = get_name.(wind_gens)
solar_gen_names = get_name.(solar_gens)
loads = collect(get_components(StaticLoad, system))
load_matrix = get_time_series_values(Scenarios, loads[1], "load", start_time = DateTime(2019, 1, 1, 23), len = 24, ignore_scaling_factors = true)

net_load = zeros(24, 10)
for s in 1:10, t in 1:24
    net_load[t,s] = value(model[:pS][solar_gen_names[1],s,t]) + value(model[:pW][wind_gen_names[1],s,t]) - load_matrix[t,s]
end

thermal_gen_names = get_name.(get_components(ThermalGen, system))
op_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, system, g)))) for g in thermal_gen_names)

for g in thermal_gen_names
    println("Gen: $g, Cost: $(op_cost[g])")
end

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