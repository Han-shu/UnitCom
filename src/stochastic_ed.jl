include("add_thermal_ED.jl")

function stochastic_ed(sys::System, optimizer, VOLL; storage_value, init_value = nothing, scenario_count, theta = nothing, start_time = DateTime(Date(2019, 1, 1)), horizon)
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
        _add_stroage!(sys, model; isED = true, storage_value = storage_value)
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