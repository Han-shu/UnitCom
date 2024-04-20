function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    eq_power_balance = _init(model, :eq_power_balance)
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    for s in scenarios, t in time_steps
        eq_power_balance[s,t] = @constraint(model, model[:expr_net_injection][s,t] == 0)
    end
    return
end

function _add_reserve_requirement_eq!(model::JuMP.Model, sys::System; isED = false)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    reserve_requirements = model[:param].reserve_requirements
    penalty = model[:param].reserve_short_penalty
    start_time = model[:param].start_time
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    penalty_spin10 = penalty["spin10"]
    penalty_res10 = penalty["res10"]
    penalty_res30 = penalty["res30"]
    @variable(model, reserve_spin10_short[s in scenarios, t in time_steps, k in 1:length(penalty_spin10)] >= 0)
    @variable(model, reserve_10_short[s in scenarios, t in time_steps, k in 1:length(penalty_res10)] >= 0)
    @variable(model, reserve_30_short[s in scenarios, t in time_steps, k in 1:length(penalty_res30)] >= 0)

    for k in eachindex(penalty_spin10)
        @constraint(model, [s in scenarios, t in time_steps], reserve_spin10_short[s,t,k] <= penalty_spin10[k].MW)
        add_to_expression!(model[:obj], sum(reserve_spin10_short[s,t,k] for s in scenarios, t in time_steps), 
                            1/length(scenarios)*penalty_spin10[k].price)
    end
    for k in eachindex(penalty_res10)
        @constraint(model, [s in scenarios, t in time_steps], reserve_10_short[s,t,k] <= penalty_res10[k].MW)
        add_to_expression!(model[:obj], sum(reserve_10_short[s,t,k] for s in scenarios, t in time_steps), 
                            1/length(scenarios)*penalty_res10[k].price)
    end
    for k in eachindex(penalty_res30)
        for s in scenarios, t in time_steps
            if k == 2
                @constraint(model, reserve_30_short[s,t,k] <= SENY_reserve[_get_offset(isED, t)])
            elseif k == length(penalty_res30)
                @constraint(model, reserve_30_short[s,t,k] <= (reserve_requirements["res30"][_get_offset(isED, t)] - SENY_reserve[_get_offset(isED, t)] - 2320))
            else
                @constraint(model,  reserve_30_short[s,t,k] <= penalty_res30[k].MW)
            end
        end
        add_to_expression!(model[:obj], sum(reserve_30_short[s,t,k] for s in scenarios, t in time_steps), 
                            1/length(scenarios)*penalty_res30[k].price)
    end
    # reserve requirement constraints
    
    @constraint(model, eq_reserve_spin10[s in scenarios, t in time_steps], 
        sum(model[:spin_10][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] for b in storage_names) + sum(reserve_spin10_short[s,t,k] for k in 1:length(penalty_spin10))
        >= reserve_requirements["spin10"][_get_offset(isED, t)])
    
    @constraint(model, eq_reserve_10[s in scenarios, t in time_steps], 
        sum(model[:spin_10][g,s,t] + model[:Nspin_10][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] for b in storage_names) + sum(reserve_10_short[s,t,k] for k in 1:length(penalty_res10)) 
        >= reserve_requirements["res10"][_get_offset(isED, t)])
    
    @constraint(model, eq_reserve_30[s in scenarios, t in time_steps],
        sum(model[:spin_30][g,s,t] + model[:Nspin_30][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_30][b,s,t] for b in storage_names) + sum(reserve_30_short[s,t,k] for k in 1:length(penalty_res30)) 
        >= reserve_requirements["res30"][_get_offset(isED, t)])
    
    return
end

function _get_offset(isED::Bool, t::Int64):Int64
    if isED
        return hour(start_time + (t-1)*Minute(5)) + 1
    else
        offset = hour(start_time)
        return (offset+t-1)%24+1
    end
end