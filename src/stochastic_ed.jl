using JuMP

function stochastic_ed(sys::System, optimizer; theta = nothing, VOLL = 1000, start_time = DateTime(Date(2019, 1, 1)), horizon = 24)
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    if isnothing(theta)
        scenario_count = 10
    else
        scenario_count = 1
    end
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL, reserve_requirement_by_hour, reserve_short_penalty)
    model[:param] = parameters
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, sys)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)

    @variable(model, curtailment[s in scenarios, t in time_steps] >= 0)

    for g in get_components(ThermalGen, sys), s in scenarios, t in time_steps
        name = get_name(g)
        @constraint(model, pg[name,s,t] >= 0) # get_active_power_limits(g).min)
        @constraint(model, pg[name,s,t] + spin_10[name,s,t] + spin_30[name,s,t] <= get_active_power_limits(g).max)
    end

    # eb_t0 = model[:init_value].eb_t0
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, sys, b)) for b in storage_names)
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)

    # Storage
    @variable(model, kb_charge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, kb_discharge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[b in storage_names, s in scenarios, t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, res_10[b in storage_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, res_30[b in storage_names, s in scenarios, t in time_steps] >= 0)
    
    @constraint(model, battery_discharge[b in storage_names, s in scenarios, t in time_steps], 
                    kb_discharge[b,s,t] + res_10[b,s,t] + res_30[b,s,t] <= kb_discharge_max[b])


    net_load = zeros(length(time_steps), length(scenarios))
    if isnothing(theta)
        for g in solar_gens
            net_load -= get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))
        end
        for g in wind_gens
            net_load -= get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))
        end
        for load in get_components(StaticLoad, sys)
            net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
        end
    else
        for g in solar_gens
            net_load -= get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))[:, theta]
        end
        for g in wind_gens
            net_load -= get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))[:, theta]
        end
        for load in get_components(StaticLoad, sys)
            net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))[:, 100-theta]
        end
    end
    net_load = max.(net_load, 0)
    
    @constraint(model, eq_pb[s in scenarios, t in time_steps], sum(pg[g,s,t] for g in thermal_gen_names) + sum(kb_discharge[b,s,t] - kb_charge[b,s,t] for b in storage_names) + curtailment[s,t] == net_load[t,s])

    if variable_cost[thermal_gen_names[1]] isa Float64
        add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                    pg[g,s,t]*variable_cost[g]
                    for g in thermal_gen_names, s in scenarios, t in time_steps))
    else
        error("Variable cost is not a float")
    end

    # Reserve requirements
    reserve_requirements = model[:param].reserve_requirements
    penalty = model[:param].reserve_short_penalty
    penalty_spin10 = penalty["spin10"]
    penalty_res10 = penalty["res10"]
    penalty_res30 = penalty["res30"]
    @variable(model, res_10_shortfall[s in scenarios, t in time_steps] >= 0)
    @variable(model, res_30_shortfall[s in scenarios, t in time_steps] >= 0)
    for s in scenarios, t in time_steps
        offset = hour(start_time + (t-1)*Minute(5)) + 1
        @constraint(model, sum(spin_10[g,s,t] for g in thermal_gen_names) 
                + sum(res_10[b,s,t] for b in storage_names) + res_10_shortfall[s,t] >= reserve_requirements["res10"][offset])
        @constraint(model, sum(spin_30[g,s,t] for g in thermal_gen_names) 
                + sum(res_30[b,s,t] for b in storage_names)+ res_30_shortfall[s,t]>= reserve_requirements["res30"][offset])
    end
    add_to_expression!(model[:obj], (1/length(scenarios))*sum(curtailment[s,t] for s in scenarios, t in time_steps), VOLL)
    add_to_expression!(model[:obj], (1/length(scenarios))*sum(res_10_shortfall[s,t] for s in scenarios, t in time_steps), 500)
    add_to_expression!(model[:obj], (1/length(scenarios))*sum(res_30_shortfall[s,t] for s in scenarios, t in time_steps), 100)

    @objective(model, Min, model[:obj])

    optimize!(model)
    return model
end



