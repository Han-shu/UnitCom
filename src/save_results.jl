function compute_LMP(sys::System, model::JuMP.Model, LMP::OrderedDict)::OrderedDict
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time

    fix!(sys, model)
    optimize!(model)

    LMP[start_time] = dual(model[:eq_power_balance][1,1])
    return LMP
end

function solution(model::JuMP.Model, thermal_gen_names::Vector, storage_names::Vector)::OrderedDict
    time_steps = model[:param].time_steps
    start_time = model[:param].start_time
    sol = OrderedDict()
    sol["ug"] = OrderedDict(g => [value(model[:ug][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["vg"] = OrderedDict(g => [value(model[:vg][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["wg"] = OrderedDict(g => [value(model[:wg][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["ϕb"] = OrderedDict(b => [value(model[:ϕb][b,t]) for t in time_steps] for b in storage_names)
    return sol
end

function fix!(sys::System, model::JuMP.Model)
    time_steps = model[:param].time_steps
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    ug = model[:ug]
    vg = model[:vg]
    wg = model[:wg]
    ϕb = model[:ϕb]
    sol = solution(model, thermal_gen_names, storage_names)
    for g in thermal_gen_names, t in time_steps
        ug_value = round(sol["ug"][g][t], digits = 1)
        vg_value = round(sol["vg"][g][t], digits = 1)
        wg_value = round(sol["wg"][g][t], digits = 1)
        ϕb_value = round(sol["ϕb"][g][t], digits = 1)
        JuMP.fix(ug[g,t], ug_value, force = true)
        JuMP.fix(vg[g,t], vg_value, force = true)
        JuMP.fix(wg[g,t], wg_value, force = true)
        JuMP.fix(ϕb[g,t], ϕb_value, force = true)
    end
    return
end