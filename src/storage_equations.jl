function _add_stroage!(sys::System, model::JuMP.Model)::Nothing
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    # model GeneraticBattery
    @assert length(get_components(BatteryEMS, sys)) == 0
    # get parameters
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, system))
    
    eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, system, b)) for b in storage_names)

    eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, system, b)) for b in storage_names)
    η = Dict(b => get_efficiency(get_component(GenericBattery, system, b)) for b in storage_names)
    pb_in_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, system, b))[:max] for b in storage_names)
    pb_out_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, system, b))[:max] for b in storage_names)

    # Variables
    # 1==discharge, 0==charge
    ϕb = @variable(model, ϕb[b in storage_names, t in time_steps], binary = true)
    pb_in = @variable(model, pb_in[b in storage_names, t in time_steps] >= 0)
    pb_out = @variable(model, pb_out[b in storage_names, t in time_steps] >= 0)
    eb = @variable(model, eb_lim[b].min <= eb[b in storage_names, t in time_steps] <= eb_lim[b].max)

    # Constraints
    # Storage charge/discharge decisions
    storage_charge_constraints = @constraint(model, [b in storage_names, t in time_steps], 
        pb_in[b,t] <= pb_in_max[b] * (1 - ϕb[b, t]))
    storage_discharge_constraints = @constraint(model, [b in storage_names, t in time_steps],
        pb_out[b, t] <= pb_out_max[b] * ϕb[b, t])
    # Storage energy update
    storage_energy_balance = _init(model, :storage_energy_balance)
    for b in storage_names, t in time_steps
        if t == 1
            storage_energy_balance[b, 1] = @constraint(model,
                eb[b, 1] == eb_t0[b] + η[b].in * pb_in[b, 1] - (1 / η[b].out) * pb_out[b, 1])
        else
            storage_energy_balance[b, t] = @constraint(model,
                eb[b, t] == eb[b, t - 1] + η[b].in * pb_in[b, t] - (1 / η[b].out) * pb_out[b, t])
        end
    end

    return 
end