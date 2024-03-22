using DataStructures, JuMP, Dates, PowerSystems
using HiGHS

include("structs.jl")
include("net_injection.jl")
include("add_renewables.jl")
include("add_thermal.jl")
include("storage_equations.jl")
include("system_equations.jl")

function _init(model::JuMP.Model, key::Symbol)::OrderedDict
    if !(key in keys(object_dictionary(model)))
        model[key] = OrderedDict()
    end
    return model[key]
end

function stochastic_uc(
    sys::System, optimizer; 
    start_time = Dates.Date(2018,1,1), scenario_count = 10, horizon = 24, 
    VOLL=5000, use_must_run=false
    )

    model = Model(optimizer)
    model[:obj] = QuadExpr()
    parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL)
    model[:param] = parameters

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
    return model  
end

model = stochastic_uc(system, HiGHS.Optimizer, start_time = DateTime(Date(2018, 7, 18)))

