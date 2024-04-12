function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    eq_power_balance = _init(model, :eq_power_balance)
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    for s in scenarios, t in time_steps
        eq_power_balance[s,t] = @constraint(model, model[:expr_net_injection][s,t] == 0)
    end
    return
end

function _add_reserve_requirement_eq!(model::JuMP.Model, sys::System)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    reserve_requirements = model[:param].reserve_requirements
    penalty = model[:param].reserve_short_penalty
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    @variable(model, reserve_spin10_short[s in scenarios, t in time_steps] >= 0)
    @variable(model, reserve_10_short[s in scenarios, t in time_steps] >= 0)
    @variable(model, reserve_30_short[s in scenarios, t in time_steps] >= 0)

    @constraint(model, eq_reserve_spin10[s in scenarios, t in time_steps], 
        sum(model[:spin_10][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] for b in storage_names) + reserve_spin10_short[s,t] >= reserve_requirements["spin10"])
    
    @constraint(model, eq_reserve_10[s in scenarios, t in time_steps], 
        sum(model[:spin_10][g,s,t] + model[:Nspin_10][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] for b in storage_names) + reserve_10_short[s,t] >= reserve_requirements["res10"])
    
    @constraint(model, eq_reserve_30[s in scenarios, t in time_steps],
        sum(model[:spin_30][g,s,t] + model[:Nspin_30][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_30][b,s,t] for b in storage_names) + reserve_30_short[s,t] >= reserve_requirements["res30"])
    
    add_to_expression!(model[:obj], sum(reserve_spin10_short[s,t] for s in scenarios, t in time_steps), 1/length(scenarios)*penalty["spin10"])
    add_to_expression!(model[:obj], sum(reserve_10_short[s,t] for s in scenarios, t in time_steps), 1/length(scenarios)*penalty["res10"])
    add_to_expression!(model[:obj], sum(reserve_30_short[s,t] for s in scenarios, t in time_steps), 1/length(scenarios)*penalty["res30"])

    return
end