function ed_model(sys::System, optimizer)
    ed_m = Model(optimizer)
    time_period = 1:24
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    @variable(ed_m, pg[g in thermal_gen_names, t in time_period] >= 0)

    for g in get_components(ThermalGen, sys), t in time_period
        name = get_name(g)
        @constraint(ed_m, pg[name, t] >= get_active_power_limits(g).min)
        @constraint(ed_m, pg[name, t] <= get_active_power_limits(g).max)
    end

    net_load = zeros(length(time_period))
    for g in get_components(RenewableGen, sys)
        net_load -= get_time_series_values(SingleTimeSeries, g, "max_active_power")[time_periods]
    end

    for g in get_components(StaticLoad, sys)
        net_load += get_time_series_values(SingleTimeSeries, g, "max_active_power")[time_periods]
    end
    
    for t in time_period
        @constraint(ed_m, sum(pg[g, t] for g in thermal_gen_names) == net_load[t])
    end 

    @objective(ed_m, Min, sum(
                   pg[get_name(g), t]^2*get_cost(get_variable(get_operation_cost(g)))[1] +
                   pg[get_name(g), t]*get_cost(get_variable(get_operation_cost(g)))[2]
                   for g in get_components(ThermalGen, sys), t in time_periods))
    optimize!(ed_m)
    return ed_m
end

pjmsys = build_system(PSISystems, "c_sys5_pjm")
results = ed_model(pjmsys, Gurobi.Optimizer)