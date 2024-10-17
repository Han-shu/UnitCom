include("../evaluate/cost.jl")

function init_ed_hour_solution(sys::System)::OrderedDict
    sol = OrderedDict()
    sol["Time"] = []
    sol["Reserve price 10Spin"] = []
    sol["Reserve price 10Total"] = []
    sol["Reserve price 30Total"] = []
    sol["Reserve price 60Total"] = []
    sol["LMP"] = []
    # sol["Operation Cost"] = []
    sol["Charge consumers"] = []
    sol["Net load"] = []
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol["Generator Dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Storage Energy"] = OrderedDict(b => [] for b in storage_names)
    sol["Curtailment"] = OrderedDict(i => [] for i in ["load", "wind", "solar"])
    sol["Energy Revenues"] = OrderedDict(g => [] for g in vcat(thermal_gen_names, storage_names))
    sol["Reserve Revenues"] = OrderedDict(g => [] for g in vcat(thermal_gen_names, storage_names))
    sol["Other Profits"] = OrderedDict(b => [] for b in ["wind", "solar", "hydro"])
    return sol
end

function init_ed_solution(sys::System)::OrderedDict
    sol = OrderedDict()
    sol["Time"] = []
    sol["LMP"] = []
    sol["Reserve price 10Spin"] = []
    sol["Reserve price 10Total"] = []
    sol["Reserve price 30Total"] = []
    sol["Reserve price 60Total"] = []
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol["Generator Dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Storage Energy"] = OrderedDict(b => [] for b in storage_names)
    return sol
end

function get_ed_hour_solution(sys::System, model::JuMP.Model, sol::OrderedDict)::OrderedDict
    push!(sol["Time"], model[:param].start_time)
    reserve_prices = _get_ED_reserve_prices(model)
    push!(sol["Reserve price 10Spin"], reserve_prices["10S"])
    push!(sol["Reserve price 10Total"], reserve_prices["10T"])
    push!(sol["Reserve price 30Total"], reserve_prices["30T"])
    push!(sol["Reserve price 60Total"], reserve_prices["60T"])
    push!(sol["LMP"], _get_ED_dual_price(model, :eq_power_balance))
    # push!(sol["Operation Cost"], _compute_ed_cost(sys, model))
    push!(sol["Charge consumers"], _compute_ed_charge(sys, model))
    push!(sol["Net load"], _compute_ed_net_load(sys, model))
    
    curtailment = _compute_ed_curtailment(sys, model)
    for i in ["load", "wind", "solar"]
        push!(sol["Curtailment"][i], curtailment[i])
    end
   
    EnergyRevenues, ReserveRevenues = _compute_ed_gen_revenue(sys, model)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    for g in thermal_gen_names
        push!(sol["Generator Dispatch"][g], value(model[:pg][g,1,1]))
        push!(sol["Energy Revenues"][g], EnergyRevenues[g])
        push!(sol["Reserve Revenues"][g], ReserveRevenues[g])
    end
    for b in storage_names
        push!(sol["Storage Energy"][b], value(model[:eb][b,1,1]))
        push!(sol["Energy Revenues"][b], EnergyRevenues[b])
        push!(sol["Reserve Revenues"][b], ReserveRevenues[b])
    end
    renewable_profits = _compute_ed_renewable_profits(sys, model)
    for b in ["wind", "solar", "hydro"]
        push!(sol["Other Profits"][b], renewable_profits[b])
    end
    return sol 
end

function _compute_ed_net_load(sys::System, model::JuMP.Model)::Float64
    forecast_load = model[:forecast_load]
    solar_gen_names = get_name.(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
    wind_gen_names = get_name.(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
    net_load = forecast_load[1,1]
    net_load = net_load - sum(value(model[:pS][g,1,1]) for g in solar_gen_names) - sum(value(model[:pW][g,1,1]) for g in wind_gen_names)
    return net_load
end

function merge_ed_solution(ed_sol::OrderedDict, ed_hour_sol::OrderedDict)::OrderedDict
    for key in keys(ed_hour_sol)
        if key == "Time"
            push!(ed_sol[key], ed_hour_sol[key][1])
        elseif key in ["Generator Dispatch", "Storage Energy"]
            for g in keys(ed_hour_sol[key])
                push!(ed_sol[key][g], ed_hour_sol[key][g][end])
            end   
        elseif key in ["LMP", "Reserve price 10Spin", "Reserve price 10Total", "Reserve price 30Total", "Reserve price 60Total"]
            push!(ed_sol[key], ed_hour_sol[key])
        else
            continue
        end
    end
    return ed_sol
end



function init_solution_uc(sys::System)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol = OrderedDict()
    sol["Time"] = []
    sol["Hourly average LMP"] = []
    sol["Hourly average reserve price 10Spin"] = []
    sol["Hourly average reserve price 10Total"] = []
    sol["Hourly average reserve price 30Total"] = []
    sol["Hourly average reserve price 60Total"] = []
    # sol["System operator cost"] = []
    sol["Charge consumers"] = []
    sol["Curtailment"] = OrderedDict(i => [] for i in ["load", "wind", "solar"])
    sol["Generator Dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Energy Revenues"] = OrderedDict(g => [] for g in vcat(thermal_gen_names, storage_names))
    sol["Reserve Revenues"] = OrderedDict(g => [] for g in vcat(thermal_gen_names, storage_names))
    sol["Storage Energy"] = OrderedDict(b => [] for b in storage_names)
    sol["Other Profits"] = OrderedDict(b => [] for b in ["wind", "solar", "hydro"])
    sol["Commitment status"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Start up"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Shut down"] = OrderedDict(g => [] for g in thermal_gen_names)
    return sol
end

function get_solution_uc(sys::System, model::JuMP.Model, ed_sol::OrderedDict, sol::OrderedDict)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    push!(sol["Time"], model[:param].start_time)
    push!(sol["Hourly average LMP"], mean(ed_sol["LMP"]))
    push!(sol["Hourly average reserve price 10Spin"], mean(ed_sol["Reserve price 10Spin"]))
    push!(sol["Hourly average reserve price 10Total"], mean(ed_sol["Reserve price 10Total"]))
    push!(sol["Hourly average reserve price 30Total"], mean(ed_sol["Reserve price 30Total"]))
    push!(sol["Hourly average reserve price 60Total"], mean(ed_sol["Reserve price 60Total"]))
    # sys_cost = mean(ed_sol["Operation Cost"])
    push!(sol["Charge consumers"], mean(ed_sol["Charge consumers"]))
    # gen_profits, sys_cost = minus_uc_integer_cost_thermal_gen(sys, model, ed_sol["Generator Profits"], sys_cost)
    # push!(sol["System operator cost"], sys_cost)
    for i in ["load", "wind", "solar"]
        push!(sol["Curtailment"][i], mean(ed_sol["Curtailment"][i]))
    end
    
    for b in ["wind", "solar", "hydro"]
        push!(sol["Other Profits"][b], mean(ed_sol["Other Profits"][b]))
    end
    
    for g in thermal_gen_names
        push!(sol["Generator Dispatch"][g], mean(ed_sol["Generator Dispatch"][g]))
        push!(sol["Energy Revenues"][g], mean(ed_sol["Energy Revenues"][g]))
        push!(sol["Reserve Revenues"][g], mean(ed_sol["Reserve Revenues"][g]))
        push!(sol["Commitment status"][g], Int(round(value(model[:ug][g,1]), digits=0)))
        push!(sol["Start up"][g], Int(round(value(model[:vg][g,1]), digits=0)))
        push!(sol["Shut down"][g], Int(round(value(model[:wg][g,1]), digits=0)))
    end
    
    for b in storage_names
        push!(sol["Storage Energy"][b], mean(ed_sol["Storage Energy"][b]))
        push!(sol["Energy Revenues"][b], mean(ed_sol["Energy Revenues"][b]))
        push!(sol["Reserve Revenues"][b], mean(ed_sol["Reserve Revenues"][b]))
    end
    return sol
end



# function _initiate_solution_uc_t(sys::System)::OrderedDict
#     thermal_gen_names = get_name.(get_components(ThermalGen, sys))
#     storage_names = get_name.(get_components(GenericBattery, sys))
#     sol = OrderedDict()
#     sol["Time"] = []
#     sol["Generator Dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
#     sol["Commitment status"] = OrderedDict(g => [] for g in thermal_gen_names)
#     sol["Start up"] = OrderedDict(g => [] for g in thermal_gen_names)
#     sol["Shut down"] = OrderedDict(g => [] for g in thermal_gen_names)
#     sol["Batter charge"] = OrderedDict(b => [] for b in storage_names)
#     sol["Batter discharge"] = OrderedDict(b => [] for b in storage_names)
#     sol["Batter energy"] = OrderedDict(b => [] for b in storage_names)
#     sol["Wind energy"] = []
#     sol["Solar energy"] = []
#     sol["Curtailed energy"] = []
#     sol["LMP"] = []
#     return sol
# end

# function get_solution_uc_t(sys::System, model::JuMP.Model, sol::OrderedDict)::OrderedDict
#     @info "Reoptimize with fixed integer variables ..."
#     fix!(sys, model)
#     thermal_gen_names = get_name.(get_components(ThermalGen, sys))
#     for g in thermal_gen_names, t in model[:param].time_steps
#         unset_binary(model[:ug][g,t])
#     end 
#     optimize!(model)

#     storage_names = get_name.(get_components(GenericBattery, sys))
#     push!(sol["Time"], model[:param].start_time)
#     for g in thermal_gen_names
#         push!(sol["Generator Dispatch"][g], value(model[:t_pg][g]))
#         push!(sol["Commitment status"][g], value(model[:ug][g,1]))
#         push!(sol["Start up"][g], value(model[:vg][g,1]))
#         push!(sol["Shut down"][g], value(model[:wg][g,1]))
#     end

#     for b in storage_names
#         push!(sol["Batter charge"][b], value(model[:t_kb_charge][b]))
#         push!(sol["Batter discharge"][b], value(model[:t_kb_discharge][b]))
#         push!(sol["Batter energy"][b], value(model[:t_eb][b]))
#     end
    
#     # wind_gen_names = get_name.(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
#     # solar_gen_names = get_name.(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
#     # push!(sol["Wind energy"], value(model[:t_pW][wind_gen_names[1]]))
#     # push!(sol["Solar energy"], value(model[:t_pS][solar_gen_names[1]]))
#     push!(sol["Curtailed energy"], value.(model[:curtailment][:,1]))
#     LMP = 0.0
#     for s in model[:param].scenarios
#         if abs(dual(model[:eq_power_balance][s,1])) > 0.0
#             LMP = dual(model[:eq_power_balance][s,1])
#             break
#         end
#     end
#     push!(sol["LMP"], LMP)
#     return sol
# end

# function get_integer_solution(model::JuMP.Model, thermal_gen_names::Vector)::OrderedDict
#     time_steps = model[:param].time_steps
#     sol = OrderedDict()
#     sol["ug"] = OrderedDict(g => [value(model[:ug][g,t]) for t in time_steps] for g in thermal_gen_names)
#     sol["vg"] = OrderedDict(g => [value(model[:vg][g,t]) for t in time_steps] for g in thermal_gen_names)
#     sol["wg"] = OrderedDict(g => [value(model[:wg][g,t]) for t in time_steps] for g in thermal_gen_names)
#     return sol
# end

# function get_solution_uc(sys::System, model::JuMP.Model)::OrderedDict
#     thermal_gen_names = get_name.(get_components(ThermalGen, sys))
#     time_steps = model[:param].time_steps
#     sol = OrderedDict()
#     sol["ug"] = OrderedDict(g => [value(model[:ug][g,t]) for t in time_steps] for g in thermal_gen_names)
#     sol["vg"] = OrderedDict(g => [value(model[:vg][g,t]) for t in time_steps] for g in thermal_gen_names)
#     sol["wg"] = OrderedDict(g => [value(model[:wg][g,t]) for t in time_steps] for g in thermal_gen_names)
#     return sol
# end
