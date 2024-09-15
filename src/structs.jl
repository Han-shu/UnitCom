mutable struct PriceMW
    price
    MW
end

mutable struct Parameters
    time_steps::UnitRange{Int}
    scenarios::UnitRange{Int}
    reserve_types::Vector{String}
    start_time::DateTime
    VOLL::Int
    reserve_requirements::Dict
    reserve_short_penalty::Dict
end

function _construct_model_parameters(horizon::Int, scenario_count::Int, start_time::DateTime, VOLL::Int, reserve_requirements, reserve_short_penalty)
    reserve_types = ["10S", "10N", "30S", "30N"]
    return Parameters(1:horizon, 1:scenario_count, reserve_types, start_time, VOLL, reserve_requirements, reserve_short_penalty)
end


mutable struct UCInitValue
    ug_t0::Dict
    Pg_t0::Dict
    eb_t0::Dict
    history_vg::Dict{String, Vector}
    history_wg::Dict{String, Vector}
end


mutable struct EDInitValue
    ug_t0::Dict
    vg_t0::Dict
    wg_t0::Dict
    Pg_t0::Dict
    eb_t0::Dict
end