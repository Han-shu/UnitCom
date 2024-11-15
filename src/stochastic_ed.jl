using JuMP

function stochastic_ed(sys::System, optimizer, VOLL; uc_op_price, init_value = nothing, scenario_count = 11, theta = nothing, start_time = DateTime(Date(2019, 1, 1)), horizon = 12)
    model = Model(optimizer)
    set_silent(model)
    model[:obj] = QuadExpr()
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL)
    model[:param] = parameters
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    reserve_types = model[:param].reserve_types
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
        model[:init_value] = init_value
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
    @variable(model, rg[g in thermal_gen_names, r in reserve_types, s in scenarios, t in time_steps] >= 0)

    must_run_gen_names = get_name.(get_components(x -> PSY.get_must_run(x), ThermalGen, sys))
    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1) # determine the commitment status index
        if isnothing(init_value)
            if g in must_run_gen_names
                @constraint(model, pg[g,s,t] >= pg_lim[g].min)
            else
                @constraint(model, pg[g,s,t] >= 0)
            end
        else
            @constraint(model, pg[g,s,t] >= pg_lim[g].min*ug[g][i])
        end
        @constraint(model, pg[g,s,t] + rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= pg_lim[g].max*ug[g][i])
    end

    # ramping constraints and reserve constraints
    
    # Non-spinning reserve qualifications, time_limits[:up] > 1 are not eligible to provide non-spinning reserve
    # Nuclear generators are not eligible to provide reserve
    non_faststart_gen_names = []
    nuclear_gen_names = []
    for g in thermal_gen_names
        generator = get_component(ThermalGen, sys, g)
        time_limits = get_time_limits(generator)
        if time_limits[:up] > 1
            push!(non_faststart_gen_names, g)
        end
        if generator.fuel == ThermalFuels.NUCLEAR
            push!(nuclear_gen_names, g)
        end
    end

    for g in non_faststart_gen_names, s in scenarios, t in time_steps, r in nonspin_reserve_types
        @constraint(model, rg[g,r,s,t] <= 0)
    end

    for g in nuclear_gen_names, s in scenarios, t in time_steps, r in reserve_types
        @constraint(model, rg[g,r,s,t] <= 0)
    end

    get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
    get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
    ramp_10 = Dict(g => get_rmp_up_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    ramp_30 = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    if !isnothing(init_value)
        for g in thermal_gen_names, s in scenarios, t in time_steps
            i = Int(div(min_step+t-1, 12)+1) # determine the commitment status index
            @constraint(model, pg[g,s,t] - (t==1 ? Pg_t0[g] : pg[g,s,t-1]) <= ramp_10[g]*ug[g][i]/2 + pg_lim[g].min*vg_min5[g][t])
            @constraint(model, (t==1 ? Pg_t0[g] : pg[g,s,t-1]) - pg[g,s,t] <= ramp_10[g]*ug[g][i]/2 + pg_lim[g].max*wg_min5[g][t])
        end
    end

    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1)
        @constraint(model, rg[g,"10S",s,t]<= ramp_10[g]*ug[g][i])
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] <= ramp_30[g]*ug[g][i])
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= 2*ramp_30[g]*ug[g][i])
        @constraint(model, rg[g,"10N",s,t]<= ramp_10[g]*(1-ug[g][i]))
        @constraint(model, rg[g,"10N",s,t]+ rg[g,"30N",s,t] <= ramp_30[g]*(1-ug[g][i]))
        @constraint(model, rg[g,"10N",s,t]+ rg[g,"30N",s,t] + rg[g,"60S",s,t] <= 2*ramp_30[g]*(1-ug[g][i]))
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= (pg_lim[g].max - pg_lim[g].min)*ug[g][i])
        @constraint(model, rg[g,"10N",s,t]+ rg[g,"30N",s,t] + rg[g,"60N",s,t] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g][i]))
    end

    # Storage
    _add_stroage!(sys, model; isED = true, eb_t0 = eb_t0, uc_op_price = uc_op_price)
    
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
    elseif theta == 0
        forecast_solar, forecast_wind, forecast_load = _get_biased_forecast_ED(first(solar_gens), first(wind_gens), load, start_time, time_steps)
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
    @variable(model, pS[g in solar_gen_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_solar[g][t,s])
    @variable(model, pW[g in wind_gen_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_wind[g][t,s])

    @variable(model, curtailment[s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_load[t,s])

    hydro = first(get_components(HydroDispatch, sys))
    hydro_dispatch = get_time_series_values(SingleTimeSeries, hydro, "hydro_power", start_time = start_time, len = length(time_steps))

    @constraint(model, eq_power_balance[s in scenarios, t in time_steps], sum(pg[g,s,t] for g in thermal_gen_names) + 
            sum(model[:kb_discharge][b,s,t] - model[:kb_charge][b,s,t] for b in storage_names) 
            + hydro_dispatch[t] + curtailment[s,t] + 2900 +
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
    @variable(model, t_rg[g in thermal_gen_names, r in reserve_types])

    @constraint(model, bind_pg[g in thermal_gen_names, s in scenarios], pg[g,s,1] == t_pg[g])
    @constraint(model, bind_rg[g in thermal_gen_names, r in reserve_types, s in scenarios], rg[g,r,s,1] == t_rg[g,r])
    
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    # Binding storage variables
    @variable(model, t_kb_charge[b in storage_names], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, t_kb_discharge[b in storage_names], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, t_eb[b in storage_names], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, t_battery_reserve[b in storage_names, r in ["10S", "30S", "60S"]], lower_bound = 0)
     
    @constraint(model, bind_kb_c[b in storage_names, s in scenarios], model[:kb_charge][b,s,1] == t_kb_charge[b])
    @constraint(model, bind_kb_d[b in storage_names, s in scenarios], model[:kb_discharge][b,s,1] == t_kb_discharge[b])
    @constraint(model, bind_ed[b in storage_names, s in scenarios], model[:eb][b,s,1] == t_eb[b])
    @constraint(model, bind_battery_reserve[b in storage_names, r in ["10S", "30S", "60S"], s in scenarios], model[:battery_reserve][b,r,s,1] == t_battery_reserve[b,r])

    # Binding renewable variables
    @variable(model, t_pS[g in solar_gen_names] >= 0)
    @variable(model, t_pW[g in wind_gen_names] >= 0)
    @constraint(model, bind_pS[g in solar_gen_names, s in scenarios], pS[g,s,1] == t_pS[g])
    @constraint(model, bind_pW[g in wind_gen_names, s in scenarios], pW[g,s,1] == t_pW[g])

    @objective(model, Min, model[:obj])

    optimize!(model)

    model_status = JuMP.primal_status(model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        println("The solution status is ", model_status)
        print_conflict(model; write_iis = true, iis_path = "/Users/hanshu/Desktop/Price_formation/Result")
    end

    return model
end

# function _get_worst_forecast_ED(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps)
#     fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
#     fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
#     fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
#     fcst_netload = fcst_load .- fcst_solar .- fcst_wind
#     worst_index = argmax(fcst_netload, dims = 2)
#     fcst_solar_worst = Dict(get_name(solar_gen) => fcst_solar[worst_index])
#     fcst_wind_worst = Dict(get_name(wind_gen) => fcst_wind[worst_index])
#     return fcst_solar_worst, fcst_wind_worst, fcst_load[worst_index]
# end

function _get_biased_forecast_ED(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps; p = 0.5)
    fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
    fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
    fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    fcst_netload = fcst_load .- fcst_solar .- fcst_wind
    worst_index = argmax(fcst_netload, dims = 2)
    fcst_solar_biased = Dict(get_name(solar_gen) => (1-p) .* mean(fcst_solar, dims = 2) + p .* fcst_solar[worst_index])
    fcst_wind_biased = Dict(get_name(wind_gen) => (1-p) .* mean(fcst_wind, dims = 2) + p .* fcst_wind[worst_index])
    fcst_load_biased = (1-p) .* mean(fcst_load, dims = 2) + p .* fcst_load[worst_index]
    return fcst_solar_biased, fcst_wind_biased, fcst_load_biased
end