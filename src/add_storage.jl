function _add_stroage!(sys::System, model::JuMP.Model)::Nothing
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    # model GeneraticBattery
    @assert length(get_components(BatteryEMS, sys)) == 0
    
    # get parameters
    eb_t0 = model[:init_value].eb_t0
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, system))
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, system, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, system, b)) for b in storage_names)
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, system, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, system, b))[:max] for b in storage_names)

    # Variables
    @variable(model, kb_charge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0)
    @variable(model, kb_discharge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[b in storage_names, s in scenarios, t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)

    @variable(model, res_10[b in storage_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, res_30[b in storage_names, s in scenarios, t in time_steps] >= 0)

    # Constraints
    # net injection
    @constraint(model, battery_charge[b in storage_names, s in scenarios, t in time_steps], kb_charge[b,s,t] + res_10[b,s,t] + res_30[b,s,t] <= kb_charge_max[b])

    expr_net_injection = model[:expr_net_injection]
    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(kb_charge[b,s,t] - kb_discharge[b,s,t] for b in storage_names), -1)
    end

    # Storage energy update
    eq_storage_energy = _init(model, :eq_storage_energy)
    for b in storage_names, s in scenarios, t in time_steps
        if t == 1
            eq_storage_energy[b,s,1] = @constraint(model,
                eb[b,s,1] == eb_t0[b] + η[b].in * kb_charge[b,s,1] - (1 / η[b].out) * kb_discharge[b,s,1])
        else
            eq_storage_energy[b, t] = @constraint(model,
                eb[b,s,t] == eb[b,s,t-1] + η[b].in * kb_charge[b,s,t] - (1 / η[b].out) * kb_discharge[b,s,t])
        end
    end

    # Enforce decsion variables for t = 1
    t_kb_charge = _init(model, :t_kb_charge)
    t_kb_discharge = _init(model, :t_kb_discharge)
    t_eb = _init(model, :t_eb)
    for b in storage_names
        t_kb_charge[b] = @variable(model, lower_bound = 0, upper_bound = kb_charge_max[b])
        t_kb_discharge[b] = @variable(model, lower_bound = 0, upper_bound = kb_discharge_max[b])
        t_eb[b] = @variable(model, lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
        for s in scenarios
            @constraint(model, kb_charge[b,s,1] == t_kb_charge[b])
            @constraint(model, kb_discharge[b,s,1] == t_kb_discharge[b])
            @constraint(model, eb[b,s,1] == t_eb[b])
        end
    end
    return 
end