function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    eq_power_balance = _init(model, :eq_power_balance)
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    for s in scenarios, t in time_steps
        eq_power_balance[s,t] = @constraint(model, model[:expr_net_injection][s,t] == 0)
    end
    return
end