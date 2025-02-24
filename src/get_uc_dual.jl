"""
    get_uc_dual(sys::System, model::JuMP.Model)
    Obtain the dual values of the energy storage energy balance constraints and power balamnce cosntraint in the UC model.
    The dual values would be used to calculate as the residual value of storage
"""

function get_uc_dual(sys::System, model::JuMP.Model)
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
    storage_names = get_name.(get_components(GenericBattery, sys))
    # Take a specific hour at hour 3
    storage_value = OrderedDict(b => sum(dual(model[:eq_storage_energy][b,s,3]) for s in scenarios) for b in storage_names)
    uc_LMP = [sum(dual(model[:eq_power_balance][s,t]) for s in scenarios) for t in time_steps]
    return storage_value, uc_LMP
end


function get_uc_prices(sys::System, model::JuMP.Model, option::String)
    if option == "fix"
        @info "Reoptimize with fixed integer variables ..."
        fix!(sys, model)
    elseif option == "relax"
        @info "Reoptimize with relaxed integer variables ..."
        relax!(sys, model)
    else
        error("The initial value is not properly set")
        return nothing
    end
    
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    optimize!(model)  
    uc_LMP = [sum(dual(model[:eq_power_balance][s,t]) for s in scenarios) for t in time_steps]
    uc_10Spin = [sum(dual(model[:eq_reserve_10Spin][s,t]) for s in scenarios) for t in time_steps]
    uc_10Total = [sum(dual(model[:eq_reserve_10Total][s,t]) for s in scenarios) for t in time_steps]
    uc_30Total = [sum(dual(model[:eq_reserve_30Total][s,t]) for s in scenarios) for t in time_steps]
    uc_60Total = [sum(dual(model[:eq_reserve_60Total][s,t]) for s in scenarios) for t in time_steps]
    return uc_LMP, uc_10Spin, uc_10Total, uc_30Total, uc_60Total
end


"""
    get_integer_solution(model::JuMP.Model, thermal_gen_names::Vector)::OrderedDict
    Obtain the integer solution of the UC model
"""

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

    for g in thermal_gen_names, t in time_steps
        JuMP.unset_binary(ug[g,t])
        JuMP.unset_binary(vg[g,t])
        JuMP.unset_binary(wg[g,t])
    end 
    return
end

"""
    relax!(sys::System, model::JuMP.Model)
    Relax all binary variables (commitment status, start up, shut down) to continuous variables between 0 and 1
"""
function relax!(sys::System, model::JuMP.Model)
    time_steps = model[:param].time_steps
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))

    # [0, 1] continuous variables
    for g in thermal_gen_names, t in time_steps
        JuMP.unfix(model[:ug][g,t])
        JuMP.unfix(model[:vg][g,t])
        JuMP.unfix(model[:wg][g,t])
        JuMP.set_lower_bound(model[:ug][g,t], 0)
        JuMP.set_upper_bound(model[:ug][g,t], 1)
        JuMP.set_lower_bound(model[:vg][g,t], 0)
        JuMP.set_upper_bound(model[:vg][g,t], 1)
        JuMP.set_lower_bound(model[:wg][g,t], 0)
        JuMP.set_upper_bound(model[:wg][g,t], 1)
    end
    return
end