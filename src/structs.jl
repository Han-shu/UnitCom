mutable struct Parameters
    time_steps::UnitRange{Int}
    scenarios::UnitRange{Int}
    start_time
    VOLL::Int
end

function _construct_model_parameters(horizon::Int, scenarios, start_time; VOLL = 1000)
    return Parameters(1:horizon, scenarios, start_time, VOLL)
end