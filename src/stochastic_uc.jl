using DataStructures, JuMP, Dates, PowerSystems
using Gurobi
include("functions.jl")
include("structs.jl")
include("stochastic_ed.jl")
include("get_init_value.jl")
include("add_net_injection.jl")
include("add_imports.jl")
include("add_hydro.jl")
include("add_thermal.jl")
include("add_storage.jl")
include("add_system_eqs.jl")
include("compute_conflict.jl")
include("../NYGrid/manual_data_entries.jl")

function stochastic_uc(
    sys::System, optimizer, VOLL; 
    start_time, scenario_count, horizon, 
    use_must_run=true, init_value=nothing,
    )
    
    model = Model(optimizer)
    set_silent(model)
    model[:obj] = QuadExpr()
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL)
    model[:param] = parameters

    model[:init_value] = init_value

    _add_net_injection!(sys, model)

    _add_imports!(sys, model)

    _add_hydro!(sys, model)
    
    _add_thermal_generators!(sys, model, use_must_run)

    # Storage
    if length(get_components(GenericBattery, sys)) != 0 || length(get_components(BatteryEMS, sys)) != 0
        _add_stroage!(sys::System, model::JuMP.Model)   
    end

    _add_power_balance_eq!(model)

    _add_reserve_requirement_eq!(sys, model)

    @objective(model, Min, model[:obj])

    optimize!(model)

    model_status = JuMP.primal_status(model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        print_conflict(model; write_iis = true, iis_path = "/Users/hanshu/Desktop/Price_formation/Result")
    end

    return model  
end

