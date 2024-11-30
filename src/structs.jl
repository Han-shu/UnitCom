# include("../NYGrid/manual_data_entries.jl") 

mutable struct PriceMW
    price
    MW
end

mutable struct Parameters
    time_steps::UnitRange{Int}
    scenarios::UnitRange{Int}
    reserve_types::Vector{String}
    spin_reserve_types::Vector{String}
    nonspin_reserve_types::Vector{String}
    start_time::DateTime
    VOLL::Int
    reserve_products::Vector{String}
    reserve_requirements::Dict
    reserve_short_penalty::Dict
end

function _construct_model_parameters(horizon::Int, scenario_cnt::Int, start_time::DateTime, VOLL::Int)
    return Parameters(1:horizon, 1:scenario_cnt, reserve_types, spin_reserve_types, nonspin_reserve_types, start_time, VOLL, reserve_products, nyca_reserve_requirement, reserve_short_penalty)
end


mutable struct UCInitValue
    ug_t0::Dict
    Pg_t0::Dict
    eb_t0::Dict
    history_vg::Dict{String, Vector}
    history_wg::Dict{String, Vector}
    history_LMP::Vector
end


mutable struct EDInitValue
    ug_t0::Dict
    vg_t0::Dict
    wg_t0::Dict
    Pg_t0::Dict
    eb_t0::Dict
end