using JuMP

function stochastic_ed(sys::System, optimizer, VOLL; uc_op_price, init_value = nothing, scenario_count, theta = nothing, start_time = DateTime(Date(2019, 1, 1)), horizon)
    model = Model(optimizer)
    set_silent(model)
    model[:obj] = QuadExpr()
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL)
    model[:param] = parameters
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    reserve_types = model[:param].reserve_types
    spin_reserve_types = model[:param].spin_reserve_types
    min_step = minute(model[:param].start_time)/5
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    if !isnothing(init_value)
        model[:init_value] = init_value
    end

    # net load = load - wind - solar
    _add_net_injection!(sys, model; theta = theta)

    _add_imports!(sys, model)

    _add_hydro!(sys, model)

    # Thermal generators
    _add_thermal_generators_ED!(sys, model)

    # Storage
    if length(get_components(GenericBattery, sys)) != 0 || length(get_components(BatteryEMS, sys)) != 0
        _add_stroage!(sys, model; isED = true, uc_op_price = uc_op_price)
    end
    
    # Power balance constraints
    _add_power_balance_eq!(model)

    # Reserve requirements
    _add_reserve_requirement_eq!(sys, model; isED = true)

    # Binding decision variables at t = 1
    _add_binding_constraints!(sys, model)

    @objective(model, Min, model[:obj])

    optimize!(model)

    model_status = JuMP.primal_status(model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        println("The solution status is ", model_status)
        print_conflict(model; write_iis = true, iis_path = "/Users/hanshu/Desktop/Price_formation/Result")
    end

    return model
end

function _add_binding_constraints!(sys::System, model::JuMP.Model)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    reserve_types = model[:param].reserve_types
    spin_reserve_types = model[:param].spin_reserve_types
    min_step = minute(model[:param].start_time)/5
    
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys)
    wind_gen_names = get_name.(wind_gens)
    solar_gen_names = get_name.(solar_gens)

    pg = model[:pg]
    rg = model[:rg]
    pS = model[:pS]
    pW = model[:pW]
    kb_charge = model[:kb_charge]
    kb_discharge = model[:kb_discharge]
    eb = model[:eb]
    battery_reserve = model[:battery_reserve]   

    # Enforce decsion variables for t = 1
    # Binding thermal variables
    @variable(model, t_pg[g in thermal_gen_names])
    @variable(model, t_rg[g in thermal_gen_names, r in reserve_types])

    @constraint(model, bind_pg[g in thermal_gen_names, s in scenarios], pg[g,s,1] == t_pg[g])
    @constraint(model, bind_rg[g in thermal_gen_names, r in reserve_types, s in scenarios], rg[g,r,s,1] == t_rg[g,r])
    
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    # Binding storage variables
    @variable(model, t_kb_charge[b in storage_names], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, t_kb_discharge[b in storage_names], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, t_eb[b in storage_names], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, t_battery_reserve[b in storage_names, r in spin_reserve_types], lower_bound = 0)
     
    @constraint(model, bind_kb_c[b in storage_names, s in scenarios], model[:kb_charge][b,s,1] == t_kb_charge[b])
    @constraint(model, bind_kb_d[b in storage_names, s in scenarios], model[:kb_discharge][b,s,1] == t_kb_discharge[b])
    @constraint(model, bind_ed[b in storage_names, s in scenarios], model[:eb][b,s,1] == t_eb[b])
    @constraint(model, bind_battery_reserve[b in storage_names, r in spin_reserve_types, s in scenarios], model[:battery_reserve][b,r,s,1] == t_battery_reserve[b,r])

    # Binding renewable variables
    @variable(model, t_pS[g in solar_gen_names] >= 0)
    @variable(model, t_pW[g in wind_gen_names] >= 0)
    @constraint(model, bind_pS[g in solar_gen_names, s in scenarios], pS[g,s,1] == t_pS[g])
    @constraint(model, bind_pW[g in wind_gen_names, s in scenarios], pW[g,s,1] == t_pW[g])
    return 
end


function _add_thermal_generators_ED!(sys::System, model::JuMP.Model)
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    horizon = length(time_steps)
    reserve_types = model[:param].reserve_types
    spin_reserve_types = model[:param].spin_reserve_types
    min_step = minute(model[:param].start_time)/5
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))

    # initial value
    init_value = nothing
    if !haskey(model, :init_value)
        ug = Dict(g => [1, 1] for g in thermal_gen_names) # Assume all thermal generators are on
        vg = Dict(g => [0, 0] for g in thermal_gen_names) # Assume all thermal generators are started up before
        wg = Dict(g => [0, 0] for g in thermal_gen_names)
        Pg_t0 = Dict(g => get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names) # all 0
    else
        init_value = model[:init_value]
        ug = init_value.ug_t0 # commitment status, 2-element Vector, 1 for on, 0 for off
        vg = init_value.vg_t0 # startup status, 2-element Vector
        wg = init_value.wg_t0 # shutdown status, 2-element Vector
        Pg_t0 = init_value.Pg_t0
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

    for g in thermal_gen_names, s in scenarios, t in time_steps
        add_to_expression!(model[:expr_net_injection][s,t], pg[g,s,t], 1.0)
    end

    @assert isa(variable_cost[thermal_gen_names[1]], Float64)
    for g in thermal_gen_names, s in scenarios, t in time_steps
        add_to_expression!(model[:obj], pg[g,s,t]*variable_cost[g], 1/length(scenarios))
    end

    return 
end