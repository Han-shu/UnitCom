function _add_power_balance_eq!(model::JuMP.Model)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    @constraint(model, eq_power_balance[s in scenarios, t in time_steps], model[:expr_net_injection][s,t] == 0)
    return
end

function _add_reserve_requirement_eq!(sys::System, model::JuMP.Model; isED = false)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    reserve_products = model[:param].reserve_products # = ["10Spin", "10Total", "30Total", "60Total"]
    reserve_requirements = model[:param].reserve_requirements
    penalty = model[:param].reserve_short_penalty
    start_time = model[:param].start_time
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    new_reserve_requirement = _get_new_reserve_rerquirement(sys, model, POLICY, isED)
    # set different penalty multiplier for ED and UC model
    multiplier = isED ? 1 : 1

    @variable(model, reserve_short[rr in reserve_products, s in scenarios, t in time_steps, k in 1:length(penalty[rr])] >= 0)

    # reserve short constraints
    for rr in reserve_products # ["10Spin", "10Total", "30Total", "60Total"]
        if rr in ["10Spin", "10Total"] 
            for k in eachindex(penalty[rr])
                @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= penalty[rr][k].MW)
                add_to_expression!(model[:obj], sum(reserve_short[rr,s,t,k] for s in scenarios, t in time_steps), 
                                            multiplier * penalty[rr][k].price/length(scenarios))
            end
        elseif rr == "30Total"
            for k in eachindex(penalty[rr])
                if (POLICY == "DR30") && (k == length(penalty[rr]))
                    @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= penalty[rr][k].MW + new_reserve_requirement[t])
                else
                    @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= penalty[rr][k].MW)
                end
                add_to_expression!(model[:obj], sum(reserve_short[rr,s,t,k] for s in scenarios, t in time_steps), 
                                            multiplier * penalty[rr][k].price/length(scenarios))
            end
        elseif (POLICY == "DR60") && (rr == "60Total")
            for k in eachindex(penalty[rr])
                @constraint(model, [s in scenarios, t in time_steps], reserve_short[rr,s,t,k] <= new_reserve_requirement[t])
                add_to_expression!(model[:obj], sum(reserve_short[rr,s,t,k] for s in scenarios, t in time_steps), 
                                                multiplier * penalty[rr][k].price/length(scenarios))
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
    
    if POLICY == "DR30"
        @constraint(model, eq_reserve_30Total[s in scenarios, t in time_steps],
            sum(model[:rg][g,"10S",s,t] + model[:rg][g,"10N",s,t] + model[:rg][g,"30S",s,t] + model[:rg][g,"30N",s,t] for g in thermal_gen_names) + 
            sum(model[:battery_reserve][b,"10S",s,t] + model[:battery_reserve][b,"30S",s,t] for b in storage_names) + 
            sum(reserve_short["30Total",s,t,k] for k in 1:length(penalty["30Total"])) 
            >= reserve_requirements["30Total"] + new_reserve_requirement[t])
    else
        @constraint(model, eq_reserve_30Total[s in scenarios, t in time_steps],
            sum(model[:rg][g,"10S",s,t] + model[:rg][g,"10N",s,t] + model[:rg][g,"30S",s,t] + model[:rg][g,"30N",s,t] for g in thermal_gen_names) + 
            sum(model[:battery_reserve][b,"10S",s,t] + model[:battery_reserve][b,"30S",s,t] for b in storage_names) + 
            sum(reserve_short["30Total",s,t,k] for k in 1:length(penalty["30Total"])) 
            >= reserve_requirements["30Total"])
    end
    
    if POLICY == "DR60"
        @constraint(model, eq_reserve_60Total[s in scenarios, t in time_steps],
            sum(model[:rg][g,"60S",s,t] + model[:rg][g,"60N",s,t] for g in thermal_gen_names) + 
            sum(model[:battery_reserve][b,"60S",s,t] for b in storage_names) + 
            sum(reserve_short["60Total",s,t,k] for k in 1:length(penalty["60Total"])) 
            >= new_reserve_requirement[t])
    else
        @constraint(model, eq_reserve_60Total[s in scenarios, t in time_steps],
            sum(model[:rg][g,"60S",s,t] + model[:rg][g,"60N",s,t] for g in thermal_gen_names) + 
            sum(model[:battery_reserve][b,"60S",s,t] for b in storage_names) + 
            sum(reserve_short["60Total",s,t,k] for k in 1:length(penalty["60Total"])) 
            >= 0)
    end

    return
end



function  _get_new_reserve_rerquirement(sys::System, model::JuMP.Model, policy::String, isED::Bool)::Vector{Float64}
    if policy in ["SB", "MF", "WF", "BF", "PF"]
        return [0.0 for t in model[:param].time_steps]
    elseif policy[1:2] =="BF"
        return [0.0 for t in model[:param].time_steps]
    elseif policy == "DR60" || policy == "DR30"
        netload_diff = _get_mean_fcst_netload_diff(sys, model, isED)
        return netload_diff
    else
        error("Policy $policy is not defined")
    end
end

function _get_mean_fcst_netload_diff(sys::System, model::JuMP.Model, isED::Bool)::Vector{Float64}
    start_time = model[:param].start_time
    time_steps = model[:param].time_steps
    solar_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
    wind_gen = first(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
    load = first(get_components(StaticLoad, sys))
    fcst_solar = get_time_series_values(Scenarios, solar_gen, "solar_power", start_time = start_time, len = length(time_steps))
    fcst_wind = get_time_series_values(Scenarios, wind_gen, "wind_power", start_time = start_time, len = length(time_steps))
    fcst_load = get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_steps))
    fcst_netload = fcst_load .- fcst_solar .- fcst_wind
    
    mean_fcst_netload = vec(mean(fcst_netload, dims = 2))
    max_fcst_netload = vec(maximum(fcst_netload, dims = 2))
    fcst_netload_diff = max_fcst_netload - mean_fcst_netload

    # worst_index = argmax(fcst_netload, dims = 2)
    # fcst_netload_diff2 = fcst_netload[worst_index] .- mean(fcst_netload, dims = 2)
    # @assert abs(fcst_netload_diff .- fcst_netload_diff2) .< 1e-6 
    
    if !isED
        if fcst_netload_diff[1] < 1e-2
            fcst_netload_diff[1] = model[:init_value].uncertainty_reserve
        end
        model[:init_value].uncertainty_reserve = fcst_netload_diff[2]
    end
    return fcst_netload_diff
end