function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    @constraint(model, eq_power_balance[s in scenarios, t in time_steps], model[:expr_net_injection][s,t] == 0)
    return
end

function _add_reserve_requirement_eq!(sys::System, model::JuMP.Model; isED = false)::Nothing
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

    # 5 min = 1/12 hour
    multiplier = isED ? 1/(length(scenarios)*12) : 1/length(scenarios)

    for k in eachindex(penalty_spin10)
        @constraint(model, [s in scenarios, t in time_steps], reserve_spin10_short[s,t,k] <= penalty_spin10[k].MW)
        add_to_expression!(model[:obj], sum(reserve_spin10_short[s,t,k] for s in scenarios, t in time_steps), 
                            penalty_spin10[k].price*multiplier)
    end
    for k in eachindex(penalty_res10)
        @constraint(model, [s in scenarios, t in time_steps], reserve_10_short[s,t,k] <= penalty_res10[k].MW)
        add_to_expression!(model[:obj], sum(reserve_10_short[s,t,k] for s in scenarios, t in time_steps), 
                            penalty_res10[k].price*multiplier)
    end
    for k in eachindex(penalty_res30)
        for s in scenarios, t in time_steps
            if k == 2
                @constraint(model, reserve_30_short[s,t,k] <= SENY_reserve[_get_offset(isED,t,start_time)])
            elseif k == length(penalty_res30)
                @constraint(model, reserve_30_short[s,t,k] <= (reserve_requirements["res30"][_get_offset(isED,t,start_time)] - SENY_reserve[_get_offset(isED,t,start_time)] - 2320))
            else
                @constraint(model,  reserve_30_short[s,t,k] <= penalty_res30[k].MW)
            end
        end
        add_to_expression!(model[:obj], sum(reserve_30_short[s,t,k] for s in scenarios, t in time_steps), 
                            penalty_res30[k].price*multiplier)
    end
    
    # reserve requirement constraints
    @constraint(model, eq_reserve_spin10[s in scenarios, t in time_steps], 
        sum(model[:spin_10][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] for b in storage_names) + sum(reserve_spin10_short[s,t,k] for k in 1:length(penalty_spin10))
        >= reserve_requirements["spin10"][_get_offset(isED,t,start_time)])
    
    @constraint(model, eq_reserve_10[s in scenarios, t in time_steps], 
        sum(model[:spin_10][g,s,t] + model[:Nspin_10][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] for b in storage_names) + sum(reserve_10_short[s,t,k] for k in 1:length(penalty_res10)) 
        >= reserve_requirements["res10"][_get_offset(isED,t,start_time)])
    
    @constraint(model, eq_reserve_30[s in scenarios, t in time_steps],
        sum(model[:spin_10][g,s,t] + model[:Nspin_10][g,s,t] + model[:spin_30][g,s,t] + model[:Nspin_30][g,s,t] for g in thermal_gen_names) + 
        sum(model[:res_10][b,s,t] + model[:res_30][b,s,t] for b in storage_names) + sum(reserve_30_short[s,t,k] for k in 1:length(penalty_res30)) 
        >= reserve_requirements["res30"][_get_offset(isED,t,start_time)])
    
    return
end

function _get_offset(isED::Bool, t::Int64, start_time::DateTime):Int64
    if isED
        return hour(start_time + (t-1)*Minute(5)) + 1
    else
        offset = hour(start_time)
        return (offset+t-1)%24+1
    end
end