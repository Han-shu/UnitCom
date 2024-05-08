function _add_hydro!(sys::System, model::JuMP.Model)::Nothing
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    start_time = model[:param].start_time
    hydro = first(get_components(HydroDispatch, sys))
    hydro_dispatch = get_time_series_values(SingleTimeSeries, hydro, "hydro_power", start_time = start_time, len = length(time_steps))
    for s in scenarios, t in time_steps
        add_to_expression!(model[:expr_net_injection][s,t], hydro_dispatch[t], 1.0)
    end
    return
end