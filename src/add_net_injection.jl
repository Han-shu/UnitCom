function _add_net_injection!(sys::System, model::JuMP.Model; theta::Union{Nothing, Int64} = nothing)::Nothing
    expr_net_injection = _init(model, :expr_net_injection)

    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    VOLL = model[:param].VOLL

    load = first(get_components(StaticLoad, sys))
    
    if isnothing(theta)
        if length(scenarios) == 1
            load_matrix = mean(get_time_series_values(Scenarios, load, "load", start_time = start_time, 
                                                        len = length(time_steps)), dims = 2)
        else
            load_matrix = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
        end
    # elseif theta == 100
    #     solar_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
    #     wind_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
    #     load_matrix = _get_worst_load(solar_gen, wind_gen, load, start_time, time_steps)
    elseif theta == 0
        solar_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
        wind_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
        load_matrix = _get_biased_load(solar_gen, wind_gen, load, start_time, time_steps)
    else
        load_matrix = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))[:, theta]
    end
    
    for s in scenarios, t in time_steps
        expr_net_injection[s,t] = AffExpr()
        add_to_expression!(expr_net_injection[s,t], load_matrix[t,s] - 2900, -1.0) # 2900MW is imports
    end


    # Load curtailment
    @variable(model, curtailment[s in scenarios, t in time_steps], lower_bound = 0, upper_bound = load_matrix[t,s])
    for s in scenarios, t in time_steps   
        add_to_expression!(expr_net_injection[s,t], curtailment[s,t], 1.0)
        add_to_expression!(model[:obj], VOLL*curtailment[s,t], 1/length(scenarios))
    end

    return
end

# function _get_worst_load(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps)
#     fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
#     fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
#     fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
#     fcst_netload = fcst_load .- fcst_solar .- fcst_wind
#     worst_index = argmax(fcst_netload, dims = 2)
#     fcst_load_worst = fcst_load[worst_index]
#     return fcst_load_worst
# end

function _get_biased_load(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps; p = 0.5)
    fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
    fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
    fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    fcst_netload = fcst_load .- fcst_solar .- fcst_wind
    worst_index = argmax(fcst_netload, dims = 2)
    fcst_load_biased = (1-p) .* mean(fcst_load, dims = 2) + p .* fcst_load[worst_index]
    return fcst_load_biased
end
