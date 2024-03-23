function _get_init_value(sys::System)::InitValue
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    ug_t0 = Dict(g => PSY.get_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    Pg_t0 = Dict(g => PSY.get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, system, b)) for b in storage_names)
    return _construct_init_value(ug_t0, Pg_t0, eb_t0)
end

function _get_init_value(sys::System, model::JuMP.Model)::InitValue
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    ug_t0 = Dict(g => value(model[:ug][g, 1]) for g in thermal_gen_names)
    #TODO: pg[g,s,t] average or make each scenario the same
    Pg_t0 = Dict(g => value(model[:pg][g, 1, 1]) for g in thermal_gen_names)
    eb_t0 = Dict(b => value(model[:init_value][b]) for b in storage_names)
    return _construct_init_value(ug_t0, Pg_t0, eb_t0)
end

# function _get_init_value(sys::System, model::JuMP.Model)::InitValue
#     storage_names = PSY.get_name.(get_components(GenericBattery, sys))
#     thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))

#     if isnothing(model)
#         ug_t0 = Dict(g => PSY.get_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
#         Pg_t0 = Dict(g => PSY.get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
#         eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, system, b)) for b in storage_names)
#     else
#         ug_t0 = Dict(g => value(model[:ug][g, 1]) for g in thermal_gen_names)
#         Pg_t0 = Dict(g => value(model[:pg][g, 1]) for g in thermal_gen_names)
#         eb_t0 = Dict(b => value(model[:init_value][b]) for b in storage_names)
#     end
#     return _construct_init_value(ug_t0, Pg_t0, eb_t0)
# end