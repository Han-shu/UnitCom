function initiate_solution_uc_t(sys::System)::OrderedDict
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    sol = OrderedDict()
    sol["Time"] = []
    sol["Generator energy dispatch"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Commitment status"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Start up"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Shut down"] = OrderedDict(g => [] for g in thermal_gen_names)
    sol["Batter charge"] = OrderedDict(b => [] for b in storage_names)
    sol["Batter discharge"] = OrderedDict(b => [] for b in storage_names)
    sol["Batter energy"] = OrderedDict(b => [] for b in storage_names)
    sol["Wind energy"] = []
    sol["Solar energy"] = []
    sol["Curtailed energy"] = []
    sol["LMP"] = []
    return sol
end

function get_solution_uc_t(sys::System, model::JuMP.Model, sol::OrderedDict)::OrderedDict
    @info "Reoptimize with fixed integer variables ..."
    fix!(sys, model)
    optimize!(model)

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    push!(sol["Time"], model[:param].start_time)
    for g in thermal_gen_names
        push!(sol["Generator energy dispatch"][g], value(model[:t_pg][g]))
        push!(sol["Commitment status"][g], value(model[:ug][g,1]))
        push!(sol["Start up"][g], value(model[:vg][g,1]))
        push!(sol["Shut down"][g], value(model[:wg][g,1]))
    end

    for b in storage_names
        push!(sol["Batter charge"][b], value(model[:t_kb_charge][b]))
        push!(sol["Batter discharge"][b], value(model[:t_kb_discharge][b]))
        push!(sol["Batter energy"][b], value(model[:t_eb][b]))
    end
    
    wind_gen_names = get_name.(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, sys))
    solar_gen_names = get_name.(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, sys))
    push!(sol["Wind energy"], value(model[:t_pW][wind_gen_names[1]]))
    push!(sol["Solar energy"], value(model[:t_pS][solar_gen_names[1]]))
    push!(sol["Curtailed energy"], value.(model[:curtailment][:,1]))
    push!(sol["LMP"], dual(model[:eq_power_balance][1,1]))
    return sol
end

function get_integer_solution(model::JuMP.Model, thermal_gen_names::Vector)::OrderedDict
    time_steps = model[:param].time_steps
    sol = OrderedDict()
    sol["ug"] = OrderedDict(g => [value(model[:ug][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["vg"] = OrderedDict(g => [value(model[:vg][g,t]) for t in time_steps] for g in thermal_gen_names)
    sol["wg"] = OrderedDict(g => [value(model[:wg][g,t]) for t in time_steps] for g in thermal_gen_names)
    return sol
end

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