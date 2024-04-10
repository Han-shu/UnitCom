function _add_net_injection!(model::JuMP.Model, sys::System)::Nothing
    expr_net_injection = _init(model, :expr_net_injection)

    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    VOLL = model[:param].VOLL

    loads = collect(get_components(StaticLoad, sys))
    # Load curtailment
    @variable(model, curtailment[s in scenarios, t in time_steps], lower_bound = 0)
    for s in scenarios, t in time_steps
        expr_net_injection[s,t] = AffExpr()
        add_to_expression!(expr_net_injection[s,t], curtailment[s,t], 1.0)
        add_to_expression!(model[:obj], VOLL*curtailment[s,t], 1/length(scenarios))
    end

    for load in loads
        load_matrix = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
        for s in scenarios, t in time_steps
            add_to_expression!(expr_net_injection[s,t], load_matrix[t,s], -1.0)
        end
    end

    # Enforce decsion variables for t = 1
    @variable(model, t_curtailment, lower_bound = 0) 
    for s in scenarios
        @constraint(model, curtailment[s,1] == t_curtailment)
    end
    return
end

    # # net load
    # net_load = zeros(length(time_steps), length(scenarios))
    # for load in loads
    #     net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    # end

    # eq_power_balance = _init(model, :eq_power_balance)
    # if has_storage
    #     #TODO power balance constraints with storage
    #     for s in scenarios, t in time_steps
    #         eq_power_balance[s,t] = @constraint(model, sum(pg[g,s,t] for g in thermal_gen_names) 
    #             + sum(pW[g,s,t] for g in wind_gen_names) + sum(pS[g,s,t] for g in solar_gen_names) 
    #             + curtailment[s,t] == net_load[t,s])
    #     end 
    # else
    #     for s in scenarios, t in time_steps
    #         eq_power_balance[s,t] = @constraint(model, sum(pg[g,s,t] for g in thermal_gen_names) 
    #             + sum(pW[g,s,t] for g in wind_gen_names) + sum(pS[g,s,t] for g in solar_gen_names) 
    #             + curtailment[s,t] == net_load[t,s])
    #     end 
    # end