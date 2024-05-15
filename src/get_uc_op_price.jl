"""
    get_uc_op_price(sys::System, model::JuMP.Model)
    Obtain the dual values of the energy storage energy balance constraints in the UC model.
    The dual values would be used to calculate as the residual value of storage
"""

function get_uc_op_price(sys::System, model::JuMP.Model)::Vector
    @info "Reoptimize with fixed integer variables ..."
    fix!(sys, model)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    for g in thermal_gen_names, t in time_steps
        unset_binary(model[:ug][g,t])
        unset_binary(model[:vg][g,t])
        unset_binary(model[:wg][g,t])
    end 
    optimize!(model)
    # LMP = [sum(dual(model[:eq_power_balance][s,t]) for s in scenarios) for t in time_steps]
    op_price = [sum(dual(model[:eq_storage_energy]["BA",s,t]) for s in scenarios) for t in time_steps]
    return op_price
end

function get_integer_solution(model::JuMP.Model, thermal_gen_names::Vector)::OrderedDict
    time_steps = model[:param].time_steps
    sol = OrderedDict()
    sol["ug"] = OrderedDict(g => [value(model[:ug][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["vg"] = OrderedDict(g => [value(model[:vg][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["wg"] = OrderedDict(g => [value(model[:wg][g,t]) for t in time_steps] for g in thermal_gen_names)
    return sol
end


"""
    fix!(sys::System, model::JuMP.Model)
    Fix all binary variables (commitment status, start up, shut down) to the integer solution
"""

function fix!(sys::System, model::JuMP.Model)
    time_steps = model[:param].time_steps
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    sol = get_integer_solution(model, thermal_gen_names)
    ug = model[:ug]
    vg = model[:vg]
    wg = model[:wg]
    for g in thermal_gen_names, t in time_steps
        ug_value = round(sol["ug"][g][t])
        vg_value = round(sol["vg"][g][t])
        wg_value = round(sol["wg"][g][t])
        JuMP.fix(ug[g,t], ug_value, force = true)
        JuMP.fix(vg[g,t], vg_value, force = true)
        JuMP.fix(wg[g,t], wg_value, force = true)
    end
    return
end