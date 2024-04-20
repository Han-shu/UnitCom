using JuMP

function stochastic_ed(sys::System, optimizer; init_value = nothing, theta = nothing, VOLL = 1000, start_time = DateTime(Date(2019, 1, 1)), horizon = 24)
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
    storage_names = get_name.(get_components(GenericBattery, sys))

    if isnothing(init_value)
        ug = Dict(g => 1 for g in thermal_gen_names)
        Pg_t0 = Dict(g => get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
        eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, sys, b)) for b in storage_names)
    else
        ug = init_value.ug_t0 # commitment status
        Pg_t0 = init_value.Pg_t0
        eb_t0 = init_value.eb_t0
    end
    # Thermal generators
    pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)

    for g in thermal_gen_names, s in scenarios, t in time_steps
        @constraint(model, pg[g,s,t] >= pg_lim[g].min*ug[g])
        @constraint(model, pg[g,s,t] + spin_10[g,s,t] + spin_30[g,s,t] <= pg_lim[g].max*ug[g])
    end

    # ramping constraints and reserve constraints
    get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
    get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
    ramp_up = Dict(g => get_rmp_up_limit(get_component(thermal_type, sys, g))*60 for g in thermal_gen_names)
    ramp_dn = Dict(g => get_rmp_dn_limit(get_component(thermal_type, sys, g))*60 for g in thermal_gen_names)
    for g in thermal_gen_names, s in scenarios, t in time_steps
        if t == 1
            @constraint(model, pg[g,s,1] - Pg_t0[g] + spin_10[g,s,1] + spin_30[g,s,1] <= ramp_up[g]*ug[g,1])
            @constraint(model, Pg_t0[g] - pg[g,s,1]  <= ramp_dn[g]*ug[g,1]/12)
        else
            @constraint(model, pg[g,s,t] - pg[g,s,t-1] + spin_10[g,s,t] + spin_30[g,s,t] <= ramp_up[g]*ug[g,t])
            @constraint(model, pg[g,s,t-1] - pg[g,s,t] <= ramp_dn[g]*ug[g,t]/12)
        end
        @constraint(model, spin_10[g,s,1] <= ramp_up[g]*ug[g,t]/6)
        @constraint(model, spin_10[g,s,1] + spin_30[g,s,1] <= ramp_up[g]*ug[g,t]/2)
        @constraint(model, Nspin_10[g,s,1] <= ramp_up[g]*(1-ug[g,t])/6)
        @constraint(model, Nspin_10[g,s,1] + Nspin_30[g,s,1] <= ramp_up[g]*(1-ug[g,t])/2)
        @constraint(model, spin_10[g,s,1] + spin_30[g,s,1] <= (pg_lim[g].max - pg_lim[g].min)*ug[g,t])
        @constraint(model, Nspin_10[g,s,1] + Nspin_30[g,s,1] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g,t]))
    end

    # Storage
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, sys, b)) for b in storage_names)
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)

    @variable(model, kb_charge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, kb_discharge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[b in storage_names, s in scenarios, t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, res_10[b in storage_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, res_30[b in storage_names, s in scenarios, t in time_steps] >= 0)

    @constraint(model, battery_discharge[b in storage_names, s in scenarios, t in time_steps], 
                    kb_discharge[b,s,t] + res_10[b,s,t] + res_30[b,s,t] <= kb_discharge_max[b])
    
    eq_storage_energy = _init(model, :eq_storage_energy)
    for b in storage_names, s in scenarios, t in time_steps
        if t == 1
            eq_storage_energy[b,s,1] = @constraint(model,
                eb[b,s,1] == eb_t0[b] + η[b].in * kb_charge[b,s,1] - (1/η[b].out) * kb_discharge[b,s,1])
        else
            eq_storage_energy[b, t] = @constraint(model,
                eb[b,s,t] == eb[b,s,t-1] + η[b].in * kb_charge[b,s,t] - (1/η[b].out) * kb_discharge[b,s,t])
        end
    end

    # net load = load - wind - solar
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, sys)                
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
    @variable(model, curtailment[s in scenarios, t in time_steps] >= 0)
    @constraint(model, eq_pb[s in scenarios, t in time_steps], sum(pg[g,s,t] for g in thermal_gen_names) + sum(kb_discharge[b,s,t] - kb_charge[b,s,t] for b in storage_names) + curtailment[s,t] == net_load[t,s])

    if variable_cost[thermal_gen_names[1]] isa Float64
        add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                    pg[g,s,t]*variable_cost[g]
                    for g in thermal_gen_names, s in scenarios, t in time_steps))
    else
        error("Variable cost is not a float")
    end

    # Reserve requirements
    _add_reserve_requirement_eq!(model, sys; isED = true)

    @objective(model, Min, model[:obj])

    optimize!(model)
    return model
end



