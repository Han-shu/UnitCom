# Add net injection, expr_net_injection = - forecast_load + curtaliment + pS + pW + hydro + imports + pg + (kb_discharge - kb_charge) = 0
function _add_net_injection!(sys::System, model::JuMP.Model)::Nothing
    expr_net_injection = _init(model, :expr_net_injection)

    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    VOLL = model[:param].VOLL

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys)
    wind_gen_names = get_name.(wind_gens)
    solar_gen_names = get_name.(solar_gens)

    forecast_solar, forecast_wind, forecast_load = _get_forecast_by_policy(sys, model)

    @variable(model, pS[g in solar_gen_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_solar[g][t,s])
    @variable(model, pW[g in wind_gen_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_wind[g][t,s])

    for s in scenarios, t in time_steps
        expr_net_injection[s,t] = AffExpr()
        add_to_expression!(expr_net_injection[s,t], forecast_load[t,s], -1.0)
        add_to_expression!(expr_net_injection[s,t], sum(pS[g,s,t] for g in solar_gen_names), 1.0)
        add_to_expression!(expr_net_injection[s,t], sum(pW[g,s,t] for g in wind_gen_names), 1.0)
    end

    # Load curtailment
    @variable(model, curtailment[s in scenarios, t in time_steps], lower_bound = 0, upper_bound = forecast_load[t,s])

    for s in scenarios, t in time_steps   
        add_to_expression!(expr_net_injection[s,t], curtailment[s,t], 1.0)
        add_to_expression!(model[:obj], curtailment[s,t], VOLL/length(scenarios))
    end

    return
end

function _get_biased_forecast(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps)
    @assert POLICY[1:2] == "BF" || error("Policy $POLICY is not a biased forecast policy")
    if length(POLICY) == 2
        p = 0.5
    else
        p = parse(Int64, POLICY[3:end])/10
        @assert 0 <= p <= 1 || error("Policy $POLICY is not a valid biased forecast policy")
    end
    @info "Biased forecast with p = $p"
    fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
    fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
    fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    fcst_netload = fcst_load .- fcst_solar .- fcst_wind
    worst_index = argmax(fcst_netload, dims = 2)
    fcst_solar_biased = Dict(get_name(solar_gen) => (1-p) .* mean(fcst_solar, dims = 2) + p .* fcst_solar[worst_index])
    fcst_wind_biased = Dict(get_name(wind_gen) => (1-p) .* mean(fcst_wind, dims = 2) + p .* fcst_wind[worst_index])
    fcst_load_biased = (1-p) .* mean(fcst_load, dims = 2) + p .* fcst_load[worst_index]
    return fcst_solar_biased, fcst_wind_biased, fcst_load_biased
end

# return forecast_solar, forecast_wind, forecast_load according to theta and length(scenarios)
function _get_forecast_by_policy(sys::System, model::JuMP.Model)
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    scenarios = model[:param].scenarios

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys)
    load = first(get_components(StaticLoad, sys))

    if POLICY == "SB"
        forecast_solar = Dict(get_name(g) => 
                get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))
                for g in solar_gens)
        forecast_wind = Dict(get_name(g) => 
            get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))
            for g in wind_gens)
        forecast_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    elseif POLICY in ["MF", "DR60", "DR30"]
        forecast_solar = Dict(get_name(g) => 
            mean(get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps)), dims = 2)
            for g in solar_gens)
        forecast_wind = Dict(get_name(g) =>
            mean(get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps)), dims = 2)
            for g in wind_gens)
        forecast_load = mean(get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps)), dims = 2)
    elseif POLICY[1:2] == "BF"
        forecast_solar, forecast_wind, forecast_load = _get_biased_forecast(first(solar_gens), first(wind_gens), load, start_time, time_steps)
    elseif POLICY in ["PF", "WF"]
        theta = POLICY == "PF" ? 1 : 11
        forecast_solar = Dict(get_name(g) => 
            get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps))[:, theta]
            for g in solar_gens)
        forecast_wind = Dict(get_name(g) => 
            get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))[:, theta]
            for g in wind_gens)
        forecast_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))[:, theta]
    else
        error("Policy $POLICY is not defined")
    end
    return forecast_solar, forecast_wind, forecast_load
end


