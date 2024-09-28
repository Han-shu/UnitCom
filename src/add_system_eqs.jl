function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    @constraint(model, eq_power_balance[s in scenarios, t in time_steps], model[:expr_net_injection][s,t] == 0)
    return
end

function _add_reserve_requirement_eq!(sys::System, model::JuMP.Model; isED = false)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    reserve_products = model[:param].reserve_products
    reserve_requirements = model[:param].reserve_requirements
    penalty = model[:param].reserve_short_penalty
    start_time = model[:param].start_time
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    @variable(model, reserve_short[rr in reserve_products, s in scenarios, t in time_steps, k in 1:length(penalty[rr])] >= 0)
    
    # 5 min = 1/12 hour
    multiplier = isED ? 1/(length(scenarios)*12) : 1/length(scenarios)

    # reserve short constraints
    for rr in reserve_products
        for k in eachindex(penalty[rr])
            @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= penalty[rr][k].MW)
            add_to_expression!(model[:obj], sum(reserve_short[rr,s,t,k] for s in scenarios, t in time_steps), 
                                        penalty[rr][k].price*multiplier)
        end
    end
    
    # reserve requirement constraints
    @constraint(model, eq_reserve_10Spin[s in scenarios, t in time_steps], 
        sum(model[:rg][g,"10S",s,t] for g in thermal_gen_names) + 
        sum(model[:battery_reserve][b,"10S",s,t] for b in storage_names) + sum(reserve_short["10Spin",s,t,k] for k in 1:length(penalty["10Spin"]))
        >= reserve_requirements["10Spin"])
    
    @constraint(model, eq_reserve_10Total[s in scenarios, t in time_steps], 
        sum(model[:rg][g,"10S",s,t] + model[:rg][g,"10N",s,t] for g in thermal_gen_names) + 
        sum(model[:battery_reserve][b,"10S",s,t] for b in storage_names) + sum(reserve_short["10Total",s,t,k] for k in 1:length(penalty["10Total"])) 
        >= reserve_requirements["10Total"])
    
    @constraint(model, eq_reserve_30Total[s in scenarios, t in time_steps],
        sum(model[:rg][g,"10S",s,t] + model[:rg][g,"10N",s,t] + model[:rg][g,"30S",s,t] + model[:rg][g,"30N",s,t] for g in thermal_gen_names) + 
        sum(model[:battery_reserve][b,"10S",s,t] + model[:battery_reserve][b,"30S",s,t] for b in storage_names) + 
        sum(reserve_short["30Total",s,t,k] for k in 1:length(penalty["30Total"])) 
        >= reserve_requirements["30Total"])
    
    @constraint(model, eq_reserve_60Total[s in scenarios, t in time_steps],
        sum(model[:rg][g,"60S",s,t] + model[:rg][g,"60N",s,t] for g in thermal_gen_names) + 
        sum(model[:battery_reserve][b,"60S",s,t] for b in storage_names) + 
        sum(reserve_short["60Total",s,t,k] for k in 1:length(penalty["60Total"])) 
        >= reserve_requirements["60Total"])

    return
end

# function _get_offset(isED::Bool, t::Int64, start_time::DateTime):Int64
#     if isED
#         return hour(start_time + (t-1)*Minute(5)) + 1
#     else
#         offset = hour(start_time)
#         return (offset+t-1)%24+1
#     end
# end