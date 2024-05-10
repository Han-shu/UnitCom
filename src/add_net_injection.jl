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
    else
        load_matrix = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))[:, theta]
    end
    
    for s in scenarios, t in time_steps
        expr_net_injection[s,t] = AffExpr()
        add_to_expression!(expr_net_injection[s,t], load_matrix[t,s], -1.0)
    end


    # Load curtailment
    @variable(model, curtailment[s in scenarios, t in time_steps], lower_bound = 0, upper_bound = load_matrix[t,s])
    for s in scenarios, t in time_steps   
        add_to_expression!(expr_net_injection[s,t], curtailment[s,t], 1.0)
        add_to_expression!(model[:obj], VOLL*curtailment[s,t], 1/length(scenarios))
    end

    return
end