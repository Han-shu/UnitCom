using JuMP

function stochastic_ed(sys::System, optimizer; uc_LMP, init_value = nothing, scenario_count = 10, theta = nothing, VOLL = 5000, start_time = DateTime(Date(2019, 1, 1)), horizon = 12)
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL, reserve_requirement_by_hour, reserve_short_penalty)
    model[:param] = parameters
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    min_step = minute(model[:param].start_time)/5
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    # Get initial conditions
    if isnothing(init_value)
        ug = Dict(g => [1, 1] for g in thermal_gen_names) # Assume all thermal generators are on
        vg = Dict(g => [0, 0] for g in thermal_gen_names) # Assume all thermal generators are started up before
        wg = Dict(g => [0, 0] for g in thermal_gen_names)
        Pg_t0 = Dict(g => get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names) # all 0
        eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, sys, b)) for b in storage_names)
    else
        ug = init_value.ug_t0 # commitment status, 2-element Vector, 1 for on, 0 for off
        vg = init_value.vg_t0 # startup status, 2-element Vector
        wg = init_value.wg_t0 # shutdown status, 2-element Vector
        Pg_t0 = init_value.Pg_t0
        eb_t0 = init_value.eb_t0
    end

    vg_min5 = Dict(g => zeros(horizon) for g in thermal_gen_names)
    wg_min5 = Dict(g => zeros(horizon) for g in thermal_gen_names)

    minute(model[:param].start_time) == 0 ? idx = 1 : idx = 2
    for t in time_steps
        if minute(model[:param].start_time + Minute(5)*(t-1)) == 0
            for g in thermal_gen_names
                vg_min5[g][t] = vg[g][idx]
                wg_min5[g][t] = wg[g][idx]
            end
            break
        end
    end

    # Thermal generators
    pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps])
    @variable(model, spin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, Nspin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, Nspin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)

    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1) # determine the commitment status index
        if isnothing(init_value)
            @constraint(model, pg[g,s,t] >= 0)
        else
            @constraint(model, pg[g,s,t] >= pg_lim[g].min*ug[g][i])
        end
        @constraint(model, pg[g,s,t] + spin_10[g,s,t] + spin_30[g,s,t] <= pg_lim[g].max*ug[g][i])
    end

    # ramping constraints and reserve constraints
    get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
    get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
    ramp_10 = Dict(g => get_rmp_up_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    ramp_30 = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    if !isnothing(init_value)
        #TODO startup and shutdown ramping 
    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1) # determine the commitment status index
        @constraint(model, pg[g,s,t] - (t==1 ? Pg_t0[g] : pg[g,s,t-1]) + spin_10[g,s,t]/2 + spin_30[g,s,t]/6 <= ramp_10[g]*ug[g][i]/2 + pg_lim[g].min*vg_min5[g][t])
        @constraint(model, (t==1 ? Pg_t0[g] : pg[g,s,t-1]) - pg[g,s,t] <= ramp_10[g]*ug[g][i]/2 + pg_lim[g].max*wg_min5[g][t])
    end
    end

    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1)
        @constraint(model, spin_10[g,s,t] <= ramp_10[g]*ug[g][i])
        @constraint(model, spin_10[g,s,t] + spin_30[g,s,t] <= ramp_30[g]*ug[g][i])
        @constraint(model, Nspin_10[g,s,t] <= ramp_10[g]*(1-ug[g][i]))
        @constraint(model, Nspin_10[g,s,t] + Nspin_30[g,s,t] <= ramp_30[g]*(1-ug[g][i]))
        @constraint(model, spin_10[g,s,t] + spin_30[g,s,t] <= (pg_lim[g].max - pg_lim[g].min)*ug[g][i])
        @constraint(model, Nspin_10[g,s,t] + Nspin_30[g,s,t] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g][i]))
    end

    # Storage
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, sys, b)) for b in storage_names)
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)

    @variable(model, kb_charge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_charge_max[b]) # power capacity MW
    @variable(model, kb_discharge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[b in storage_names, s in scenarios, t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, res_10[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0)
    @variable(model, res_30[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0)

    @constraint(model, battery_discharge[b in storage_names, s in scenarios, t in time_steps], 
                    kb_discharge[b,s,t] + res_10[b,s,t] + res_30[b,s,t] <= kb_discharge_max[b])

    # energy capacity MWh
    @constraint(model, eq_storage_energy[b in storage_names, s in scenarios, t in time_steps],
        eb[b,s,t] == (t == 1 ? eb_t0[b] : eb[b,s,t-1]) + η[b].in * kb_charge[b,s,t]/12 - (1/η[b].out) * kb_discharge[b,s,t]/12)

    # Add residual value of storage
    add_to_expression!(model[:obj], sum(eb[b,s,last(time_steps)] for b in storage_names, s in scenarios), -uc_LMP[2]/length(scenarios))

    # net load = load - wind - solar - hydro
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, sys) 
    solar_gen_names = get_name.(solar_gens)
    wind_gen_names = get_name.(wind_gens)               
    load = first(get_components(StaticLoad, sys))
    if isnothing(theta)
        if length(scenarios) == 1
            forecast_solar = Dict(get_name(g) => 
                mean(get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps)), dims = 2)
                for g in solar_gens)
            forecast_wind = Dict(get_name(g) =>
                mean(get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps)), dims = 2)
                for g in wind_gens)
            forecast_load = mean(get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps)), dims = 2)
        else
            forecast_solar = Dict(get_name(g) =>
                get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps)) 
                for g in solar_gens)
            forecast_wind = Dict(get_name(g) =>
                get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))
                for g in wind_gens)
            forecast_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
        end
    else
        forecast_solar = Dict(get_name(g) =>
            get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))[:, theta]
            for g in solar_gens)
        forecast_wind = Dict(get_name(g) =>
        get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))[:, theta]
            for g in wind_gens)
        forecast_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))[:, theta]          
    end
    
    model[:forecast_load] = forecast_load
    @variable(model, pS[g in solar_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, pW[g in wind_gen_names, s in scenarios, t in time_steps] >= 0)
    @constraint(model, solar_constraint[g in solar_gen_names, s in scenarios, t in time_steps], pS[g,s,t] <= forecast_solar[g][t,s])
    @constraint(model, wind_constraint[g in wind_gen_names, s in scenarios, t in time_steps], pW[g,s,t] <= forecast_wind[g][t,s])

    @variable(model, curtailment[s in scenarios, t in time_steps] >= 0)

    hydro = first(get_components(HydroDispatch, sys))
    hydro_dispatch = get_time_series_values(SingleTimeSeries, hydro, "hydro_power", start_time = start_time, len = length(time_steps))

    @constraint(model, eq_power_balance[s in scenarios, t in time_steps], sum(pg[g,s,t] for g in thermal_gen_names) + 
            sum(kb_discharge[b,s,t] - kb_charge[b,s,t] for b in storage_names) 
            + hydro_dispatch[t] + curtailment[s,t] + 
            sum(pS[g,s,t] for g in solar_gen_names) + sum(pW[g,s,t] for g in wind_gen_names) == forecast_load[t,s])

    if variable_cost[thermal_gen_names[1]] isa Float64
        add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                    pg[g,s,t]*variable_cost[g]/12
                    for g in thermal_gen_names, s in scenarios, t in time_steps))
    else
        error("Variable cost is not a float")
    end

    # Reserve requirements
    _add_reserve_requirement_eq!(sys, model; isED = true)

    add_to_expression!(model[:obj], sum(curtailment[s,t] for s in scenarios, t in time_steps), VOLL/(12*length(scenarios)))
    
    # Enforce decsion variables for t = 1
    # Binding thermal variables
    @variable(model, t_pg[g in thermal_gen_names])
    @variable(model, t_spin_10[g in thermal_gen_names])
    @variable(model, t_spin_30[g in thermal_gen_names])
    @variable(model, t_Nspin_10[g in thermal_gen_names])
    @variable(model, t_Nspin_30[g in thermal_gen_names])

    @constraint(model, bind_pg[g in thermal_gen_names, s in scenarios], pg[g,s,1] == t_pg[g])
    @constraint(model, bind_spin10[g in thermal_gen_names, s in scenarios], spin_10[g,s,1] == t_spin_10[g])
    @constraint(model, bind_spin30[g in thermal_gen_names, s in scenarios], spin_30[g,s,1] == t_spin_30[g])
    @constraint(model, bind_Nspin10[g in thermal_gen_names, s in scenarios], Nspin_10[g,s,1] == t_Nspin_10[g])
    @constraint(model, bind_Nspin30[g in thermal_gen_names, s in scenarios], Nspin_30[g,s,1] == t_Nspin_30[g])
    
    # Binding storage variables
    @variable(model, t_kb_charge[b in storage_names], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, t_kb_discharge[b in storage_names], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, t_eb[b in storage_names], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, t_res_10[b in storage_names])
    @variable(model, t_res_30[b in storage_names])
     
    @constraint(model, bind_kb_c[b in storage_names, s in scenarios], kb_charge[b,s,1] == t_kb_charge[b])
    @constraint(model, bind_kb_d[b in storage_names, s in scenarios], kb_discharge[b,s,1] == t_kb_discharge[b])
    @constraint(model, bind_ed[b in storage_names, s in scenarios], eb[b,s,1] == t_eb[b])
    @constraint(model, bind_res10[b in storage_names, s in scenarios], res_10[b,s,1] == t_res_10[b])
    @constraint(model, bind_res30[b in storage_names, s in scenarios], res_30[b,s,1] == t_res_30[b])

    # Binding renewable variables
    # @variable(model, t_pS[g in solar_gen_names] >= 0)
    # @variable(model, t_pW[g in wind_gen_names] >= 0)

    # @constraint(model, bind_pS[g in solar_gen_names, s in scenarios], pS[g,s,1] == t_pS[g])
    # @constraint(model, bind_pW[g in wind_gen_names, s in scenarios], pW[g,s,1] == t_pW[g])

    @objective(model, Min, model[:obj])

    optimize!(model)

    model_status = JuMP.primal_status(model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        println("The solution status is ", model_status)
        print_conflict(model; write_iis = true, iis_path = "/Users/hanshu/Desktop/Price_formation/Result")
    end

    return model
end



