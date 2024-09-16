include("../src/add_renewables.jl")
function _compute_ed_curtailment(sys::System, model::JuMP.Model)::Dict
    curtailment = Dict()
    curtailment["load"] = value(model[:curtailment][1,1])
    forecast_solar, forecast_wind = _get_forecast_renewables(sys, model)
    curtailment["wind"] = forecast_wind["wind"][1,1] - value(model[:pW]["wind",1,1])
    curtailment["solar"] = forecast_solar["solar"][1,1] - value(model[:pS]["solar",1,1])
    return curtailment
end

# compute the total production cost at time t 
# binary var from UC and op var from ED
function _compute_ed_cost(sys::System, model::JuMP.Model)::Float64
    VOLL = model[:param].VOLL
    penalty = model[:param].reserve_short_penalty
    reserve_products = model[:param].reserve_products
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    
    # thermal gen: fixed_cost, shutdown_cost, startup_cost, variable_cost
    thermal_gen_op_costs = sum(variable_cost[g]*value(model[:pg][g,1,1]) for g in thermal_gen_names)
    
    lost_load_penalty = VOLL*value(model[:curtailment][1,1])
    reserve_short_penalty = sum(value(model[:reserve_short][rr,1,1,k])*penalty[rr][k].price for rr in reserve_products for k in 1:length(penalty[rr]))
    
    cost_t = thermal_gen_op_costs + lost_load_penalty + reserve_short_penalty
    return cost_t
end


# function _get_ED_dual_price(model::JuMP.Model, key::Symbol)::Float64
#     price = sum(dual(model[key][s,1]) for s in model[:param].scenarios)*12
#     return price
# end

function _get_ED_dual_price(model::JuMP.Model, key::Symbol)::Float64
    # Multiply 12 to ensure price is with unit of $/MWh
    price = sum(dual(model[key][s,1]) for s in model[:param].scenarios)*12
    return price
end

function _get_ED_reserve_prices(model::JuMP.Model)::Dict{String, Float64}
    sys_lambda_10S = _get_ED_dual_price(model, :eq_reserve_10Spin)
    sys_lambda_10T = _get_ED_dual_price(model, :eq_reserve_10Total)
    sys_lambda_30T = _get_ED_dual_price(model, :eq_reserve_30Total)
    reserve_prices = Dict("10S" => sys_lambda_10S + sys_lambda_10T + sys_lambda_30T, 
                          "10T" => sys_lambda_10T + sys_lambda_30T, "30T" => sys_lambda_30T)
    return reserve_prices
end


# compute the total charges for energy and reserves to buyers of electricity
function _compute_ed_charge(sys::System, model::JuMP.Model)::Float64
    LMP = _get_ED_dual_price(model, :eq_power_balance)
    reserve_prices = _get_ED_reserve_prices(model)

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))

    energy_charge_t = sum(LMP*value(model[:pg][g,1,1]) for g in thermal_gen_names) +
                    sum(LMP*value(model[:kb_discharge][b,1,1]) for b in storage_names)

    reserve_charge_t = sum(reserve_prices["10S"]*value(model[:rg][g,"10S",1,1]) + 
            reserve_prices["10T"]*value(model[:rg][g,"10N",1,1]) + 
            reserve_prices["30T"]*(value(model[:rg][g,"30S",1,1]) + value(model[:rg][g,"30N",1,1])) 
                        for g in thermal_gen_names) +
            sum(reserve_prices["10S"]*value(model[:battery_reserve][b,"10S",1,1]) + 
                reserve_prices["30T"]*value(model[:battery_reserve][b,"30S",1,1]) for b in storage_names)

    charge_t = energy_charge_t + reserve_charge_t

    return charge_t
end

function _compute_ed_gen_profits(sys::System, model::JuMP.Model)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    
    LMP = _get_ED_dual_price(model, :eq_power_balance)
    reserve_prices = _get_ED_reserve_prices(model)
    
    gen_profits = OrderedDict()
    for g in thermal_gen_names        
        profit = ((LMP-variable_cost[g])*value(model[:pg][g,1,1]) + 
                reserve_prices["10S"]*value(model[:rg][g,"10S",1,1]) +
                reserve_prices["10T"]*value(model[:rg][g,"10N",1,1]) + 
                reserve_prices["30T"]*(value(model[:rg][g,"30S",1,1]) + value(model[:rg][g,"30N",1,1]))) 
        gen_profits[g] = profit
    end

    storage_names = get_name.(get_components(GenericBattery, sys))
    storage_profits = OrderedDict()
    for b in storage_names
        profit = (LMP*(value(model[:kb_discharge][b,1,1])-value(model[:kb_charge][b,1,1])) + 
                reserve_prices["10S"]*value(model[:battery_reserve][b,"10S",1,1]) + 
                reserve_prices["30T"]*value(model[:battery_reserve][b,"30S",1,1]))
        storage_profits[b] = profit
    end

    return gen_profits, storage_profits
end

function _compute_ed_renewable_profits(sys::System, model::JuMP.Model)
    renewable_gen_names = get_name.(get_components(RenewableGen, sys))
    LMP = _get_ED_dual_price(model, :eq_power_balance)
    renewable_profits = OrderedDict()
    renewable_profits["wind"] = LMP*value(model[:pW]["wind",1,1])
    renewable_profits["solar"] = LMP*value(model[:pS]["solar",1,1])

    hydro = first(get_components(HydroDispatch, sys))
    hydro_dispatch = get_time_series_values(SingleTimeSeries, hydro, "hydro_power", start_time = model[:param].start_time, len = length(model[:param].time_steps))
    renewable_profits["hydro"] = LMP*hydro_dispath[1]
    return renewable_profits
end

function minus_uc_integer_cost_thermal_gen(sys::System, model::JuMP.Model, gen_profits_ed::OrderedDict, sys_cost::Float64)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    gen_profits = OrderedDict(g => mean(gen_profits_ed[g]) for g in thermal_gen_names)
    for g in thermal_gen_names
        ug = value(model[:ug][g,1])
        vg = value(model[:vg][g,1])
        wg = value(model[:wg][g,1])
        integer_cost = ug*fixed_cost[g] + vg*startup_cost[g] + wg*shutdown_cost[g]
        gen_profits[g] -= integer_cost
        sys_cost += integer_cost
    end
    return gen_profits, sys_cost
end