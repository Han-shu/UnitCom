function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    power_balance_constraints = _init(model, :power_balance_constraints)
    net_injection = _init(model, :net_injection)
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    for s in scenarios, t in time_steps
        net_injection[s,t] = @variable(model)
        power_balance_constraints[s,t] = @constraint(model, net_injection[s,t] + model[:expr_net_injection][s,t] == 0)
    end

    return
end