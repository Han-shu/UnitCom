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

    new_reserve_requirement = _get_new_reserve_rerquirement(sys, model, policy)

    @variable(model, reserve_short[rr in reserve_products, s in scenarios, t in time_steps, k in 1:length(penalty[rr])] >= 0)
    
    # 5 min = 1/12 hour
    multiplier = isED ? 1/(length(scenarios)*12) : 1/length(scenarios)

    # reserve short constraints
    for rr in reserve_products
        if rr != "60Total"
            for k in eachindex(penalty[rr])
                @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= penalty[rr][k].MW)
                add_to_expression!(model[:obj], sum(reserve_short[rr,s,t,k] for s in scenarios, t in time_steps), 
                                            penalty[rr][k].price*multiplier)
            end
        else # "60Total"
            @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= new_reserve_requirement[t])
            if ~isED
                add_to_expression!(model[:obj], sum(reserve_short[rr,s,t,k] for s in scenarios, t in time_steps), 
                                            penalty[rr][k].price*multiplier)
            end
        end
    end
    
    # reserve requirement constraints
    @constraint(model, eq_reserve_10Spin[s in scenarios, t in time_steps], 
        sum(model[:rg][g,"10S",s,t] for g in thermal_gen_names) + 
        sum(model[:battery_reserve][b,"10S",s,t] for b in storage_names) + 
        sum(reserve_short["10Spin",s,t,k] for k in 1:length(penalty["10Spin"]))
        >= reserve_requirements["10Spin"])
    
    @constraint(model, eq_reserve_10Total[s in scenarios, t in time_steps], 
        sum(model[:rg][g,"10S",s,t] + model[:rg][g,"10N",s,t] for g in thermal_gen_names) + 
        sum(model[:battery_reserve][b,"10S",s,t] for b in storage_names) + 
        sum(reserve_short["10Total",s,t,k] for k in 1:length(penalty["10Total"])) 
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
        >= new_reserve_requirement[t])

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

"""
    policy
    "SB": Stochastic benchmark, contingency reserve only, no new reserve requirement
    "NR": 50 percentile forecast
    "BNR": Biased forecast
    "FR": Fixed reserve requirement
    "DR": Dynamic reserve requirement
"""
function  _get_new_reserve_rerquirement(sys::System, model::JuMP.Model, policy::String)::Vector{Float64}
    if policy in ["SB", "NR", "BNR"]
        return [0.0 for t in model[:param].time_steps]
    elseif policy == "FR"
        return #TODO predetermined reserve requirement
    elseif policy == "DR"
        theta1 = 10
        theta2 = 6
        netload_diff = _get_fcst_netload_diff(sys, model, theta1, theta2)
        return netload_diff
    else
        error("Policy $policy is not defined")
    end
end

function _get_fcst_netload_diff(sys::System, model::JuMP.Model, theta1::Int, theta2::Int)::Vector{Float64}
    start_time = model[:param].start_time
    time_steps = model[:param].time_steps
    solar_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
    wind_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
    load = first(get_components(StaticLoad, sys))
    fcst_netload_theta1 = _get_fcst_netload_theta(solar_gen, wind_gen, load, start_time, time_steps, theta1)
    fcst_netload_theta2 = _get_fcst_netload_theta(solar_gen, wind_gen, load, start_time, time_steps, theta2)
    return fcst_netload_theta1 - fcst_netload_theta2
end


function _get_forecast_theta_vector(component, component_name, start_time, time_steps, theta)
    return get_time_series_values(Scenarios, component, component_name, start_time = start_time, len = length(time_steps))[:, theta] 
end

function _get_fcst_netload_theta(solar_gen::RenewableGen, wind_gen::RenewableGen, load::StaticLoad, start_time::DateTime, time_steps::Vector{Int}, theta::Int)
    fcst_solar_theta = _get_forecast_theta_vector(solar_gen, "solar_power", start_time, time_steps, theta)
    fcst_wind_theta = _get_forecast_theta_vector(wind_gen, "wind_power", start_time, time_steps, theta)
    fcst_load_theta = _get_forecast_theta_vector(load, "load", start_time, time_steps, theta)
    return fcst_load_theta - fcst_solar_theta - fcst_wind_theta
end
