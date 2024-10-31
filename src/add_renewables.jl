function _add_renewables!(sys::System, model::JuMP.Model; theta::Union{Nothing, Int64} = nothing)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    expr_net_injection = model[:expr_net_injection]

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys)
    wind_gen_names = get_name.(wind_gens)
    solar_gen_names = get_name.(solar_gens)

    forecast_solar, forecast_wind = _get_forecast_renewables(sys, model, theta = theta)
    @variable(model, pS[g in solar_gen_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_solar[g][t,s])
    @variable(model, pW[g in wind_gen_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_wind[g][t,s])

    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(pS[g,s,t] for g in solar_gen_names), 1.0)
        add_to_expression!(expr_net_injection[s,t], sum(pW[g,s,t] for g in wind_gen_names), 1.0)
    end

    return
end

function _get_forecast_renewables(sys::System, model::JuMP.Model; theta::Union{Nothing, Int64} = nothing)
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    scenarios = model[:param].scenarios
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys)
    if isnothing(theta)
        if length(scenarios) == 1 
            forecast_solar = Dict(get_name(g) => 
                mean(get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps)), dims = 2)
                for g in solar_gens)
            forecast_wind = Dict(get_name(g) =>
                mean(get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps)), dims = 2)
                for g in wind_gens)
        else
            forecast_solar = Dict(get_name(g) => 
                get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))
                for g in solar_gens)
            forecast_wind = Dict(get_name(g) => 
                get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))
                for g in wind_gens)
        end
    # elseif theta == 100
    #     load = first(get_components(StaticLoad, sys))
    #     forecast_solar, forecast_wind = _get_worst_renewables(first(solar_gens), first(wind_gens), load, start_time, time_steps)
    else
        forecast_solar = Dict(get_name(g) => 
            get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))[:, theta]
            for g in solar_gens)
        forecast_wind = Dict(get_name(g) => 
            get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))[:, theta]
            for g in wind_gens)
    end

    return forecast_solar, forecast_wind
end

# function _get_worst_renewables(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps)
#     fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
#     fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
#     fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
#     fcst_netload = fcst_load .- fcst_solar .- fcst_wind
#     worst_index = argmax(fcst_netload, dims = 2)
#     fcst_solar_worst = Dict(get_name(solar_gen) => fcst_solar[worst_index])
#     fcst_wind_worst = Dict(get_name(wind_gen) => fcst_wind[worst_index])
#     return fcst_solar_worst, fcst_wind_worst
# end

