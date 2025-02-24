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
    # sol["Net load"] = []
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol["Generator Dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Storage Action"] = OrderedDict(b => OrderedDict("Discharge" => [], "Charge" => []) for b in storage_names)
    sol["Storage Energy"] = OrderedDict(b => [] for b in storage_names)
    sol["Load Curtailment"] = []
    sol["Renewable Generation"] = OrderedDict(i => [] for i in ["wind", "solar"])
    sol["Imports"] = []
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
    sol["Storage Action"] = OrderedDict(b => OrderedDict("Discharge" => [], "Charge" => []) for b in storage_names)
    sol["Imports"] = []
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
    push!(sol["Charge consumers"], _compute_ed_charge(sys, model))

    push!(sol["Load Curtailment"], value(model[:curtailment][1,1]))
    push!(sol["Renewable Generation"]["wind"], value(model[:pW]["wind",1,1]))
    push!(sol["Renewable Generation"]["solar"], value(model[:pS]["solar",1,1]))
    push!(sol["Imports"], value(model[:imports][1,1,1]) + value(model[:imports][1,1,2]) + value(model[:imports][1,1,3]))

    EnergyRevenues, ReserveRevenues = _compute_ed_gen_revenue(sys, model)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    for g in thermal_gen_names
        push!(sol["Generator Dispatch"][g], value(model[:pg][g,1,1]))
        push!(sol["Energy Revenues"][g], EnergyRevenues[g])
        push!(sol["Reserve Revenues"][g], ReserveRevenues[g])
    end
    for b in storage_names
        push!(sol["Storage Action"][b]["Discharge"], value(model[:kb_discharge][b,1,1]))
        push!(sol["Storage Action"][b]["Charge"], value(model[:kb_charge][b,1,1]))
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
        elseif key == "Storage Action"
            for b in keys(ed_hour_sol[key])
                for action in keys(ed_hour_sol[key][b])
                    push!(ed_sol[key][b][action], ed_hour_sol[key][b][action])
                end
            end
        elseif key == "Imports"
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
    sol["UC LMP"] = []
    sol["Hourly average LMP"] = []
    sol["Hourly average reserve price 10Spin"] = []
    sol["Hourly average reserve price 10Total"] = []
    sol["Hourly average reserve price 30Total"] = []
    sol["Hourly average reserve price 60Total"] = []
    sol["SOC Dual"] = OrderedDict(b => [] for b in storage_names)
    sol["Charge consumers"] = []
    sol["Load Curtailment"] = []
    sol["Renewable Generation"] = OrderedDict(i => [] for i in ["wind", "solar"])
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

function get_solution_uc_ed(sys::System, model::JuMP.Model, ed_sol::OrderedDict, sol::OrderedDict, storage_value::OrderedDict, uc_LMP)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    push!(sol["Time"], model[:param].start_time)
    push!(sol["UC LMP"], uc_LMP)
    push!(sol["Hourly average LMP"], mean(ed_sol["LMP"]))
    push!(sol["Hourly average reserve price 10Spin"], mean(ed_sol["Reserve price 10Spin"]))
    push!(sol["Hourly average reserve price 10Total"], mean(ed_sol["Reserve price 10Total"]))
    push!(sol["Hourly average reserve price 30Total"], mean(ed_sol["Reserve price 30Total"]))
    push!(sol["Hourly average reserve price 60Total"], mean(ed_sol["Reserve price 60Total"]))

    # sys_cost = mean(ed_sol["Operation Cost"])
    push!(sol["Charge consumers"], mean(ed_sol["Charge consumers"]))
    # gen_profits, sys_cost = minus_uc_integer_cost_thermal_gen(sys, model, ed_sol["Generator Profits"], sys_cost)
    # push!(sol["System operator cost"], sys_cost)
    push!(sol["Load Curtailment"], mean(ed_sol["Load Curtailment"]))
    for i in ["wind", "solar"]
        push!(sol["Renewable Generation"][i], mean(ed_sol["Renewable Generation"][i]))
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
        push!(sol["SOC Dual"][b], storage_value[b])
    end
    return sol
end

function get_solution_uc(sys::System, model::JuMP.Model, sol::OrderedDict)::OrderedDict
    push!(sol["Time"], model[:param].start_time)   
   
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    for g in thermal_gen_names
        push!(sol["Generator Dispatch"][g], [value(model[:pg][g,1,t]) for t in model[:param].time_steps])
        push!(sol["Commitment status"][g], [Int(round(value(model[:ug][g,t]), digits=0)) for t in model[:param].time_steps])
        push!(sol["Start up"][g], [Int(round(value(model[:vg][g,t]), digits=0)) for t in model[:param].time_steps])
        push!(sol["Shut down"][g], [Int(round(value(model[:wg][g,t]), digits=0)) for t in model[:param].time_steps])
    end
    
    for b in storage_names
        push!(sol["Storage Energy"][b], [value(model[:eb][b,1,t]) for t in model[:param].time_steps])
    end

    fix_LMP, fix_10Spin, fix_10Total, fix_30Total, fix_60Total = get_uc_prices(sys, model, "fix")
    relax_LMP, relax_10Spin, relax_10Total, relax_30Total, relax_60Total = get_uc_prices(sys, model, "relax")

    push!(sol["LMP fix"], fix_LMP)
    push!(sol["LMP relax"], relax_LMP)
    push!(sol["UC 10Spin"], fix_10Spin)
    push!(sol["UC 10Total"], fix_10Total)
    push!(sol["UC 30Total"], fix_30Total)
    push!(sol["UC 60Total"], fix_60Total)

    return sol
end

function init_solution_uc_only(sys::System)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol = OrderedDict()
    sol["Time"] = []
    sol["LMP fix"] = []
    sol["LMP relax"] = []
    sol["UC 10Spin"] = []
    sol["UC 10Total"] = []
    sol["UC 30Total"] = []
    sol["UC 60Total"] = []

    sol["Generator Dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Commitment status"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Start up"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Shut down"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Storage Energy"] = OrderedDict(b => [] for b in storage_names)
    return sol
end