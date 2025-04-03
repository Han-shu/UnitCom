include("add_thermal_ED.jl")

function stochastic_ed(sys::System, optimizer, VOLL; 
    storage_value, init_value = nothing, 
    scenario_count, start_time, horizon)

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
    _add_net_injection!(sys, model; isED = true)

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

    # Binding decision variables at t = 1 for Policy "SB"
    if POLICY == "SB" 
        _add_binding_constraints!(sys, model)
    end

    @objective(model, Min, model[:obj])

    optimize!(model)

    model_status = JuMP.primal_status(model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        println("The solution status is ", model_status)
        print_conflict(model; write_iis = true, iis_path = "Result")
    end

    return model
end