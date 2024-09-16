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

