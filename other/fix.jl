

# Fix only lookahead commitment status from last UC solution
function _fix_lookahead_commitment!(sys::System, model::JuMP.Model; fix_len = 1)::Nothing
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    ug_t0 = model[:init_value].ug_t0
    for g in thermal_gen_names, t in 1:fix_len
        JuMP.fix(model[:ug][g,t], ug_t0[g][t+1], force = true)
    end
    return
end