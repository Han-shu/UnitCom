function _add_net_injection!(model::JuMP.Model, sys::System)::Nothing
    expr_net_injection = _init(model, :expr_net_injection)
    curtailment = _init(model, :curtail)

    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    VOLL = model[:param].VOLL

    loads = collect(get_components(PowerLoad, sys))
    for s in scenarios, t in time_steps
        expr_net_injection[s,t] = AffExpr()
        # Load curtailment
        curtailment[s,t] = @variable(model, lower_bound = 0)

        add_to_expression!(expr_net_injection[s,t], curtailment[s,t], 1.0)
        add_to_expression!(model[:obj], VOLL*curtailment[s,t], 1/length(scenarios))
    end

    for load in loads
        load_matrix = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
        for s in scenarios, t in time_steps
            add_to_expression!(expr_net_injection[s,t], load_matrix[t,s], -1.0)
        end
    end
    return
end

    # # net load
    # net_load = zeros(length(time_steps), length(scenarios))
    # for load in loads
    #     net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    # end

    # power_balance_constraints = _init(model, :power_balance_constraints)
    # if has_storage
    #     #TODO power balance constraints with storage
    #     for s in scenarios, t in time_steps
    #         power_balance_constraints[s,t] = @constraint(model, sum(pg[g,s,t] for g in thermal_gen_names) 
    #             + sum(pW[g,s,t] for g in wind_gen_names) + sum(pS[g,s,t] for g in solar_gen_names) 
    #             + curtailment[s,t] == net_load[t,s])
    #     end 
    # else
    #     for s in scenarios, t in time_steps
    #         power_balance_constraints[s,t] = @constraint(model, sum(pg[g,s,t] for g in thermal_gen_names) 
    #             + sum(pW[g,s,t] for g in wind_gen_names) + sum(pS[g,s,t] for g in solar_gen_names) 
    #             + curtailment[s,t] == net_load[t,s])
    #     end 
    # end