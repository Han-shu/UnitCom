# compute the total production cost at time t 
function compute_cost_t(model::JuMP.Model, sys::System)::Float64
    VOLL = model[:param].VOLL
    penalty = model[:param].reserve_short_penalty

    ug = model[:ug]
    vg = model[:vg]
    wg = model[:wg]

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    
    # thermal gen: fixed_cost, shutdown_cost, startup_cost, variable_cost
    thermal_gen_costs = sum(fixed_cost[g]*value(ug[g,1]) + shutdown_cost[g]*value(wg[g,1]) + startup_cost[g]*value(vg[g,1]) for g in thermal_gen_names)
    thermal_gen_costs += sum(variable_cost[g]*value(model[:pg][g,1,1]) for g in thermal_gen_names)
    
    lost_load_penalty = VOLL*value(model[:curltailment][1,1])
    reserve_short_penalty = sum(value(model[:reserve_spin10_short][1,1,k])*penalty["spin10"][k].price for k in 1:length(penalty["spin10"])) +
                            sum(value(model[:reserve_10_short][1,1,k])*penalty["res10"][k].price for k in 1:length(penalty["res10"])) +
                            sum(value(model[:reserve_30_short][1,1,k])*penalty["res30"][k].price for k in 1:length(penalty["res30"]))
    cost_t = thermal_gen_costs + lost_load_penalty + reserve_short_penalty
    return cost_t
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

# compute the total charges for energy and reserves to buyers of electricity
function compute_charge_t(model::JuMP.Model, sys::System)::Float64
    LMP = _get_price(model, :eq_power_balance)
    price_spin10 = _get_price(model, :eq_reserve_spin10)
    price_res10 = _get_price(model, :eq_reserve_res10)
    price_res30 = _get_price(model, :eq_reserve_res30)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, system))

    energy_charge_t = sum(LMP*value(model[:pg][g,1,1]) for g in thermal_gen_names) +
                    sum(LMP*value(model[:kb_discharge][b,1,1]) for b in storage_names)

    reserve_charge_t = sum(price_spin10*value(model[:spin_10][g,1,1]) + 
            price_res10*(value(model[:spin_10][g,1,1]) + value(model[:Nspin_10][g,1,1])) + 
            price_res30*(value(model[:spin_30][g,1,1]) + value(model[:Nspin_30][g,1,1])) 
                        for g in thermal_gen_names) +
            sum((price_spin10+price_res10)*value(model[:res_10][b,1,1]) + 
                price_res30*value(model[:res_30][b,1,1]) for b in storage_names)

    charge_t = energy_charge_t + reserve_charge_t

    return charge_t
end

function compute_gen_profits(model::JuMP.Model, sys::System)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    
    LMP = _get_price(model, :eq_power_balance)
    price_spin10 = _get_price(model, :eq_reserve_spin10)
    price_res10 = _get_price(model, :eq_reserve_res10)
    price_res30 = _get_price(model, :eq_reserve_res30)
    gen_profits = OrderedDict()
    
    for g in thermal_gen_names
        ug = value(model[:ug][g,1])
        vg = value(model[:vg][g,1])
        wg = value(model[:wg][g,1])
        
        profit = (LMP*value(model[:pg][g,1,1]) + 
                price_spin10*value(model[:spin_10][g,1,1]) +
                price_res10*(value(model[:spin_10][g,1,1])+value(model[:Nspin_10][g,1,1])) + 
                price_res30*(value(model[:spin_10][g,1,1]) + value(model[:Nspin_30][g,1,1]))) 
        profit -= (pg*variable_cost[g] + ug*fixed_cost[g] + vg*startup_cost[g] + wg*shutdown_cost[g])
        gen_profits[g] = profit
    end

    storage_names = get_name.(get_components(GenericBattery, sys))
    for b in storage_names
        profit = (LMP*(value(model[:kb_discharge][b,1,1])-value(model[:kb_charge][b,1,1])) + 
                (price_res10+price_spin10)*value(model[:res_10][b,1,1]) + 
                price_res30*value(model[:res_30][b,1,1]))
        gen_profits[b] = profit
    end

    return gen_profits
end