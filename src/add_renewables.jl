function _add_renewables!(model::JuMP.Model, sys::System)
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    expr_net_injection = model[:expr_net_injection]

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys)
    wind_gen_names = get_name.(wind_gens)
    solar_gen_names = get_name.(solar_gens)

    forecast_solar = Dict(get_name(g) => 
        get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
        for g in solar_gens)
    forecast_wind = Dict(get_name(g) => 
        get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
        for g in wind_gens)
    
    @variable(model, pS[g in solar_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, pW[g in wind_gen_names, s in scenarios, t in time_steps] >= 0)


    for g in solar_gen_names, s in scenarios, t in time_steps
        @constraint(model, pS[g,s,t] <= forecast_solar[g][t,s])
    end
    for g in wind_gen_names, s in scenarios, t in time_steps
        @constraint(model, pW[g,s,t] <= forecast_wind[g][t,s])
    end

    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(pS[g,s,t] for g in solar_gen_names), 1.0)
        add_to_expression!(expr_net_injection[s,t], sum(pW[g,s,t] for g in wind_gen_names), 1.0)
    end

    # Enforce decsion variables for t = 1
    # @variable(model, t_pS[g in solar_gen_names] >= 0)
    # @variable(model, t_pW[g in wind_gen_names] >= 0)
    # for g in solar_gen_names, s in scenarios
    #     @constraint(model, pS[g,s,1] == t_pS[g])
    # end
    # for g in wind_gen_names, s in scenarios
    #     @constraint(model, pW[g,s,1] == t_pW[g])
    # end

    return
end


