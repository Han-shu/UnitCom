include("../evaluate/cost.jl")

function init_solution_ed(sys::System)::OrderedDict
    sol = OrderedDict()
    sol["Spin 10min price"] = []
    sol["Reserve 10min price"] = []
    sol["Reserve 30min price"] = []
    sol["LMP"] = []
    sol["operation_cost"] = []
    sol["charge_consumers"] = []
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol["gen_profits"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["storage_profits"] = OrderedDict(b => [] for b in storage_names)
    return sol
end

function get_solution_ed(sys::System, model::JuMP.Model, sol::OrderedDict)::OrderedDict
    push!(sol["Spin 10min price"], _get_price(model, :eq_reserve_spin10))
    push!(sol["Reserve 10min price"], _get_price(model, :eq_reserve_10))
    push!(sol["Reserve 30min price"], _get_price(model, :eq_reserve_30))
    push!(sol["LMP"], _get_price(model, :eq_power_balance))
    push!(sol["operation_cost"], _compute_ed_cost(sys, model))
    push!(sol["charge_consumers"], _compute_ed_charge(sys, model))
    sol["gen_profits"], sol["storage_profits"] = compute_gen_profits_t(sys, model, sol["gen_profits"], sol["storage_profits"])
    return sol 
end


function _get_price(model::JuMP.Model, key::Symbol)::Float64
    price = 0.0
    for s in model[:param].scenarios
        if abs(dual(model[key][s,1])) > 0.0
            price = dual(model[key][s,1])
            break
        end
    end
    return price
end


function init_solution_uc(sys::System)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol = OrderedDict()
    sol["Time"] = []
    sol["System operator cost"] = []
    sol["Charge consumers"] = []
    sol["Generator profits"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Storage profits"] = OrderedDict(b => [] for b in storage_names)
    sol["Commitment status"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Start up"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Shut down"] = OrderedDict(g => [] for g in thermal_gen_names)
    return sol
end

function get_solution_uc(sys::System, model::JuMP.Model, ed_sol::OrderedDict, sol::OrderedDict)::OrderedDict
    push!(sol["Time"], model[:param].start_time)
    push!(sol["System operator cost"], sum(ed_sol["operation_cost"]))
    push!(sol["Charge consumers"], sum(ed_sol["charge_consumers"]))
    gen_profits = minus_uc_integer_cost_thermal_gen(sys, model, ed_sol["gen_profits"])
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    for b in storage_names
        push!(sol["Storage profits"][b], sum(sol["storage_profits"][b]))
    end
    for g in thermal_gen_names
        push!(sol["Generator profits"][g], gen_profits[g])
        push!(sol["Commitment status"][g], value(model[:ug][g,2]))
        push!(sol["Start up"][g], value(model[:vg][g,2]))
        push!(sol["Shut down"][g], value(model[:wg][g,2]))
    end
    return sol
end



# function _initiate_solution_uc_t(sys::System)::OrderedDict
#     thermal_gen_names = get_name.(get_components(ThermalGen, sys))
#     storage_names = get_name.(get_components(GenericBattery, sys))
#     sol = OrderedDict()
#     sol["Time"] = []
#     sol["Generator energy dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
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
#         push!(sol["Generator energy dispatch"][g], value(model[:t_pg][g]))
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
