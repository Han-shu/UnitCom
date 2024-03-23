mutable struct Parameters
    time_steps::UnitRange{Int}
    scenarios::UnitRange{Int}
    start_time::DateTime
    VOLL::Int
end

function _construct_model_parameters(horizon::Int, scenario_count::Int, start_time::DateTime, VOLL::Int)
    return Parameters(1:horizon, 1:scenario_count, start_time, VOLL)
end

mutable struct InitValue
    ug_t0::Dict
    Pg_t0::Dict
    eb_t0::Dict
end

function _construct_init_value(ug_t0::Dict, Pg_t0::Dict, eb_t0::Dict)
    return InitValue(ug_t0, Pg_t0, eb_t0)
end