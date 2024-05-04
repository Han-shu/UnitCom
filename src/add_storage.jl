function _add_stroage!(sys::System, model::JuMP.Model)::Nothing
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    # model GeneraticBattery
    @assert length(get_components(BatteryEMS, sys)) == 0
    
    # get parameters
    eb_t0 = model[:init_value].eb_t0
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, sys, b)) for b in storage_names)
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)

    # Variables
    @variable(model, kb_charge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, kb_discharge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[b in storage_names, s in scenarios, t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, res_10[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b]/6)
    @variable(model, res_30[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0)

    # Constraints
    # Battery discharge
    @constraint(model, battery_reserve[b in storage_names, s in scenarios, t in time_steps], 
                    res_10[b,s,t] + res_30[b,s,t] <= kb_discharge_max[b]/2)
    @constraint(model, battery_discharge[b in storage_names, s in scenarios, t in time_steps], 
                    kb_discharge[b,s,t] + res_10[b,s,t] + res_30[b,s,t] <= kb_discharge_max[b])
    # Storage energy update
    @constraint(model, eq_storage_energy[b in storage_names, s in scenarios, t in time_steps],
        eb[b,s,t] == (t==1 ? eb_t0[b] : eb[b,s,t-1]) + η[b].in * kb_charge[b,s,t] - (1/η[b].out) * kb_discharge[b,s,t])


    # Net injection
    expr_net_injection = model[:expr_net_injection]
    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(kb_charge[b,s,t] - kb_discharge[b,s,t] for b in storage_names), -1)
    end

    return 
end