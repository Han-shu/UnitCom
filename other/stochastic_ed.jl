function ed_model(sys::System, optimizer; VOLL = 1000, start_time = DateTime(Date(2019, 1, 1)))
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    time_periods = 1:24
    scenarios = 1:10

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, system)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_periods] >= 0)
    @variable(model, curtailment[s in scenarios, t in time_periods] >= 0)

    for g in get_components(ThermalGen, sys), s in scenarios, t in time_periods
        name = get_name(g)
        @constraint(model, pg[name,s,t] >= 0) # get_active_power_limits(g).min)
        @constraint(model, pg[name,s,t] <= get_active_power_limits(g).max)
    end

    net_load = zeros(length(time_periods), length(scenarios))
    for g in solar_gens
        net_load -= get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_periods), ignore_scaling_factors = true)
    end

    for g in wind_gens
        net_load -= get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_periods), ignore_scaling_factors = true)
    end

    for load in get_components(StaticLoad, sys)
        net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_periods), ignore_scaling_factors = true)
    end
    
    net_load = max.(net_load, 0)
    
    @constraint(model, eq_pb[s in scenarios, t in time_periods], sum(pg[g,s,t] for g in thermal_gen_names) + curtailment[s,t] == net_load[t,s])

    if variable_cost[thermal_gen_names[1]] isa Float64
        add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                    pg[g,s,t]*variable_cost[g]
                    for g in thermal_gen_names, s in scenarios, t in time_periods))
    else
        error("Variable cost is not a float")
    end

    add_to_expression!(model[:obj], (1/length(scenarios))*sum(curtailment[s,t] for s in scenarios, t in time_periods), VOLL)

    @objective(model, Min, model[:obj])

    optimize!(model)
    return model
end

model = ed_model(system, Gurobi.Optimizer, start_time = DateTime(Date(2019, 7, 18)))

# cheack infeasibility
model_status = JuMP.primal_status(model)
if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
    print_conflict(model; write_iis = false)
end

# access variable values
LMP_matrix = zeros(10, 24)
Curtail_matrix = zeros(10, 24)
for s in 1:10
    for t in 1:24
        LMP_matrix[s,t] = dual(model[:eq_pb][s,t])
        Curtail_matrix[s,t] = value(model[:curtailment][s,t])
    end
end

