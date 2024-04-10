function _add_hydro(sys::System, model::JuMP.Model)::Nothing
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    hydro_names = PSY.get_name.(get_components(PSY.HydroDispatch, sys))
    hydro = Dict(h => get_component(PSY.HydroDispatch, sys, h) for h in hydro_names)
    for h in hydro_names
        hydro[h].hydro = true
    end
    return
end