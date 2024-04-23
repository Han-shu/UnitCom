function compute_gen_profit(sys::System, solution)::OrderedDict
    thermal_struct_type = Set()
    for g in get_components(ThermalGen, system)
        push!(thermal_struct_type, typeof(g))
    end
    @assert length(thermal_struct_type) == 1
    thermal_type = first(thermal_struct_type)

    thermal_gen_names = get_name.(get_components(thermal_type, sys))
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(thermal_type, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(thermal_type, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(thermal_type, sys, g)))) for g in thermal_gen_names)
    if thermal_type == ThermalMultiStart
        categories_startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalMultiStart, sys, g))) for g in thermal_gen_names)
        startup_cost = Dict(g => sum(categories_startup_cost[g])/length(categories_startup_cost[g]) for g in thermal_gen_names)
    else
        startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    end

    thermal_gen_profits = OrderedDict()
    for g in thermal_gen_names
        profit = 0.0
        pg = solution["Generator energy dispatch"][g]
        ug = solution["Commitment status"][g]
        vg = solution["Start up"][g]
        wg = solution["Shut down"][g]
        LMP = solution["LMP"]
        profit = 0.0
        for t in eachindex(pg)
            profit += (LMP[t]*pg[t] - pg[t]*variable_cost[g])
        end
        profit -= sum(ug[t]*fixed_cost[g] + vg[t]*startup_cost[g] + wg[t]*shutdown_cost[g] for t in eachindex(pg))
        thermal_gen_profits[g] = profit
    end
    return thermal_gen_profits
end


function _read_json(path::String)::Dict
    file = open(path)
    return JSON.parse(file, dicttype = () -> DefaultOrderedDict(nothing))
end

result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
json = _read_json(joinpath(result_dir, "solution.json"))
 
thermal_gen_profits = compute_gen_profit(system, json)

# write_json(joinpath(result_dir, "thermal_gen_profits.json"), thermal_gen_profits)

