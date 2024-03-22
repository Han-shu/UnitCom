mutable struct Parameters
    time_steps::UnitRange{Int}
    scenarios::UnitRange{Int}
    start_time::DateTime
    VOLL::Int
end

function _construct_model_parameters(horizon::Int, scenario_count::Int, start_time::DateTime, VOLL::Int)
    return Parameters(1:horizon, 1:scenario_count, start_time, VOLL)
end