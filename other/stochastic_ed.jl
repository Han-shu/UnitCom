function ed_model(sys::System, optimizer; VOLL = 1000, start_time = DateTime(Date(2018, 1, 1)))
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    time_periods = 1:24
    scenarios = 1:10

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    bid_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, system)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_periods] >= 0)
    @variable(model, curtailment[s in scenarios, t in time_periods] )

    for g in get_components(ThermalGen, sys), s in scenarios, t in time_periods
        name = get_name(g)
        @constraint(model, pg[name,s,t] >= get_active_power_limits(g).min)
        @constraint(model, pg[name,s,t] <= get_active_power_limits(g).max)
    end

    net_load = zeros(length(time_periods), length(scenarios))
    for g in solar_gens
        net_load -= get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_periods))
    end

    for g in wind_gens
        net_load -= get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_periods))
    end

    for load in get_components(PowerLoad, sys)
        net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_periods))
    end
    
    for s in scenarios, t in time_periods
        @constraint(model, sum(pg[g,s,t] for g in thermal_gen_names) + curtailment[s,t] == net_load[t,s])
    end 

    add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                   pg[g,s,t]^2*bid_cost[g][1][1] + pg[g,s,t]*bid_cost[g][1][2]
                   for g in thermal_gen_names, s in scenarios, t in time_periods))

    add_to_expression!(model[:obj], (1/length(scenarios))*VOLL*sum(curtailment[s,t] for s in scenarios, t in time_periods))

    @objective(model, Min, model[:obj])

    optimize!(model)
    return model
end

model = ed_model(system, HiGHS.Optimizer, start_time = DateTime(Date(2018, 7, 18)))

# access variable values
value(model[:curtailment][10,1])
value(model[:pg]["Solitude", 1, 1])