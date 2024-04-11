function _get_init_value(sys::System)::InitValue
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    # ug_t0 = Dict(g => PSY.get_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    # Pg_t0 = Dict(g => PSY.get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    Pg_t0, ug_t0 = run_ed_model(sys)
    eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, system, b)) for b in storage_names)
    history_wg = Dict(g => Vector{Int}() for g in thermal_gen_names)
    history_vg = Dict(g => Vector{Int}() for g in thermal_gen_names)
    return _construct_init_value(ug_t0, Pg_t0, eb_t0, history_wg, history_vg)
end

function run_ed_model(system::System)
    model = ed_model(system, Gurobi.Optimizer, start_time = DateTime(Date(2019, 1, 1)))
    thermal_gen_names = get_name.(get_components(ThermalGen, system))
    Pg_t0 = Dict()
    ug_t0 = Dict()
    for g in thermal_gen_names
        val = value(model[:pg][g,1,1])
        Pg_t0[g] = val
        if val > 0
            ug_t0[g] = 1
        else
            ug_t0[g] = 0
        end
    end
    return Pg_t0, ug_t0
end

function _get_init_value(sys::System, model::JuMP.Model)::InitValue
    history_wg = model[:init_value].history_wg
    history_vg = model[:init_value].history_vg
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    ug_t0 = Dict(g => value(model[:ug][g, 1]) for g in thermal_gen_names)
    Pg_t0 = Dict(g => value(model[:t_pg][g]) for g in thermal_gen_names)
    eb_t0 = Dict(b => value(model[:t_eb][b]) for b in storage_names)
    for g in thermal_gen_names
        push!(history_vg[g], Int(value(model[:vg][g, 1])))
        push!(history_wg[g], Int(value(model[:wg][g, 1])))
    end
    return _construct_init_value(ug_t0, Pg_t0, eb_t0, history_vg, history_wg)
end