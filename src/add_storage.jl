function _add_stroage!(sys::System, model::JuMP.Model; isED = false, uc_op_price = nothing)::Nothing
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    spin_reserve_types = model[:param].spin_reserve_types
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    @assert length(get_components(BatteryEMS, sys)) == 0
    duration = isED ? 1/12 : 1
    # get initial energy level and other parameters
    if haskey(model, :init_value)
        eb_t0 = model[:init_value].eb_t0
    else
        @info("No initial value for storage, using default value (Half of the capacity)")
        eb_t0 = Dict(b => get_initial_energy(get_component(PSY.GenericBattery, sys, b)) for b in storage_names)
    end
    
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, sys, b)) for b in storage_names)
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)

    # Variables
    @variable(model, kb_charge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, kb_discharge[b in storage_names, s in scenarios, t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[b in storage_names, s in scenarios, t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, battery_reserve[b in storage_names, r in spin_reserve_types, s in scenarios, t in time_steps], lower_bound = 0)

    # Constraints
    # Sustainable time limits for reserves
    @constraint(model, eq_battery_res[b in storage_names, s in scenarios, t in time_steps], 
        (1/η[b].out)*(battery_reserve[b,"10S",s,t]/6 + battery_reserve[b,"30S",s,t]/2 + battery_reserve[b,"60S",s,t]*4) <= eb[b,s,t] - eb_lim[b].min)
    # Battery discharge
    @constraint(model, battery_discharge[b in storage_names, s in scenarios, t in time_steps], 
                    kb_discharge[b,s,t] + battery_reserve[b,"10S",s,t] + battery_reserve[b,"30S",s,t] + battery_reserve[b,"60S",s,t] <= kb_discharge_max[b])
    # Storage energy update
    @constraint(model, eq_storage_energy[b in storage_names, s in scenarios, t in time_steps],
        eb[b,s,t] == (t==1 ? eb_t0[b] : eb[b,s,t-1]) + η[b].in * kb_charge[b,s,t]*duration - (1/η[b].out) * kb_discharge[b,s,t]*duration)


    if isED
         # Add residual value of storage
        for b in storage_names
            add_to_expression!(model[:obj], sum(eb[b,s,last(time_steps)] for s in scenarios), uc_op_price[b]*12/length(scenarios))
        end
    else
        history_LMP = sort(model[:init_value].history_LMP, rev = true)
        storage_segments = 1:4
        @variable(model, eb_seg[s in scenarios, k in storage_segments], lower_bound = 0, upper_bound = eb_lim["PH"].max / length(storage_segments))
        for s in scenarios
            for k in storage_segments
                value = history_LMP[k] - history_LMP[end-k+1]
                add_to_expression!(model[:obj], eb_seg[s,k], - value/length(scenarios))
            end
            @constraint(model, sum(eb_seg[s,k] for k in storage_segments) == eb["PH", s, last(time_steps)])
        end
    end

    # Net injection
    expr_net_injection = model[:expr_net_injection]
    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(kb_charge[b,s,t] - kb_discharge[b,s,t] for b in storage_names), -1)
    end

    return 
end