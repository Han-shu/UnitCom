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
    history_vg::Dict{String, Vector}
    history_wg::Dict{String, Vector}
end

function _construct_init_value(ug_t0::Dict, Pg_t0::Dict, eb_t0::Dict, history_vg::Dict, history_wg::Dict)
    return InitValue(ug_t0, Pg_t0, eb_t0, history_vg, history_wg)
end