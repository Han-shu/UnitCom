using DataStructures, JuMP, Dates, PowerSystems
using Gurobi

include("structs.jl")
include("get_init_value.jl")
include("add_net_injection.jl")
include("add_renewables.jl")
include("add_thermal.jl")
include("add_storage.jl")
include("add_system_eqs.jl")
include("compute_conflict.jl")

function _init(model::JuMP.Model, key::Symbol)::OrderedDict
    if !(key in keys(object_dictionary(model)))
        model[key] = OrderedDict()
    end
    return model[key]
end

function stochastic_uc(
    sys::System, optimizer; 
    start_time = DateTime(2019,1,1,0), scenario_count = 10, horizon = 24, 
    VOLL=5000, use_must_run=false, init_value=nothing
    )
    
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL)
    model[:param] = parameters

    if isnothing(init_value)
        init_value = _get_init_value(sys)
    end
    model[:init_value] = init_value

    _add_net_injection!(model, sys)
    
    _add_thermal_generators!(model, sys, use_must_run)
    
    _add_renewables!(model, sys)

    # Storage
    has_storage = false
    if length(get_components(GenericBattery, sys)) != 0 || length(get_components(BatteryEMS, sys)) != 0
        has_storage = true
        _add_stroage!(sys::System, model::JuMP.Model)   
    end

    _add_power_balance_eq!(model)

    @objective(model, Min, model[:obj])

    optimize!(model)

    model_status = JuMP.primal_status(model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        print_conflict(model; write_iis = false)
    end

    return model  
end

