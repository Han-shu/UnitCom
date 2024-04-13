using JuMP

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
    @variable(model, spin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)

    @variable(model, curtailment[s in scenarios, t in time_periods] >= 0)

    for g in get_components(ThermalGen, sys), s in scenarios, t in time_periods
        name = get_name(g)
        @constraint(model, pg[name,s,t] >= 0) # get_active_power_limits(g).min)
        @constraint(model, pg[name,s,t] + spin_10[name,s,t] + spin_30[name,s,t] <= get_active_power_limits(g).max)
    end

    net_load = zeros(length(time_periods), length(scenarios))
    for g in solar_gens
        net_load -= get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_periods))
    end

    for g in wind_gens
        net_load -= get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_periods))
    end

    for load in get_components(StaticLoad, sys)
        net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_periods))
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

    @variable(model, res_10_shortfall[s in scenarios, t in time_periods] >= 0)
    @variable(model, res_30_shortfall[s in scenarios, t in time_periods] >= 0)
    @constraint(model, sum(spin_10[g,s,t] for g in thermal_gen_names, s in scenarios, t in time_periods) + res_10_shortfall[s,t] >= 2630)
    @constraint(model, sum(spin_30[g,s,t] for g in thermal_gen_names, s in scenarios, t in time_periods) + res_30_shortfall[s,t]>= 5500)

    add_to_expression!(model[:obj], (1/length(scenarios))*sum(curtailment[s,t] for s in scenarios, t in time_periods), VOLL)
    add_to_expression!(model[:obj], (1/length(scenarios))*sum(res_10_shortfall[s,t] for s in scenarios, t in time_periods), 500)
    add_to_expression!(model[:obj], (1/length(scenarios))*sum(res_30_shortfall[s,t] for s in scenarios, t in time_periods), 100)

    # Enforce decsion variables for t = 1
    # @variable(model, t_pg[g in thermal_gen_names], lower_bound = 0)
    # for g in thermal_gen_names, s in scenarios
    #     @constraint(model, pg[g,s,1] == t_pg[g])
    # end
    # @variable(model, t_curtailment, lower_bound = 0)
    # for s in scenarios
    #     @constraint(model, curtailment[s,1] == t_curtailment)
    # end

    # for s in 2:10
    #     @constraint(model, curtailment[s,1] == curtailment[1,1])
    #     for g in thermal_gen_names
    #         @constraint(model, pg[g,s,1] == pg[g,1,1])
    #     end
    # end

    @objective(model, Min, model[:obj])

    optimize!(model)
    return model
end



