# Fix all binary variables (commitment status, start up, shut down) to the integer solution
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

# Fix only lookahead commitment status from last UC solution
function _fix_lookahead_commitment!(sys::System, model::JuMP.Model; fix_len = 1)::Nothing
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    ug_t0 = model[:init_value].ug_t0
    for g in thermal_gen_names, t in 1:fix_len
        JuMP.fix(model[:ug][g,t], ug_t0[g][t+1], force = true)
    end
    return
end