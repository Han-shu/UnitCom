function _add_thermal_generators!(sys::System, model::Model, use_must_run::Bool)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    expr_net_injection = model[:expr_net_injection]

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    if typeof(get_component(ThermalGen, sys, thermal_gen_names[1])) == ThermalMultiStart
        # use cold startup cost
        startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalMultiStart, sys, g)))[:cold] for g in thermal_gen_names)
    else
        startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    end

    get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
    get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
    ramp_up = Dict(g => get_rmp_up_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    ramp_dn = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)

    # initial condition
    ug_t0 = model[:init_value].ug_t0
    Pg_t0 = model[:init_value].Pg_t0

    if use_must_run
        must_run_gen_names = get_name.(get_components(x -> PSY.get_must_run(x), ThermalGen, sys))
    end

    # -----------------------------------------------------------------------------------------  
    # Variables 
    # -----------------------------------------------------------------------------------------
    @variable(model, ug[g in thermal_gen_names, t in time_steps], binary = true) # commitment status
    @variable(model, vg[g in thermal_gen_names, t in time_steps], binary = true) # startup status
    @variable(model, wg[g in thermal_gen_names, t in time_steps], binary = true) # shutdown status

    # @constraint(model, start_up[g in thermal_gen_names, t in time_steps], vg[g,t] + wg[g,t] <= 1)
    # @variable(model, vg[g in thermal_gen_names, t in time_steps], lower_bound = 0, upper_bound = 1)
    # @variable(model, wg[g in thermal_gen_names, t in time_steps], lower_bound = 0, upper_bound = 1)
 
    # power generation variables
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps])
    # reserve variables
    @variable(model, spin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, Nspin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, Nspin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)

    # Commitment status constraints 
    @constraint(model, eq_binary[g in thermal_gen_names, t in time_steps], ug[g,t] - (t==1 ? ug_t0[g] : ug[g,t-1]) == vg[g,t] - wg[g,t])

    # must run generators 
    if use_must_run
        for g in must_run_gen_names, t in time_steps
            fix(ug[g,t], 1.0; force = true)
        end
    end

    # energy dispatch constraints 
    for g in thermal_gen_names, s in scenarios, t in time_steps
        @constraint(model, pg[g,s,t] >= pg_lim[g].min*ug[g,t])
        @constraint(model, pg[g,s,t] + spin_10[g,s,t] + spin_30[g,s,t] <= pg_lim[g].max*ug[g,t])
    end

    # ramping constraints and reserve constraints
    for g in thermal_gen_names, s in scenarios, t in time_steps
        @constraint(model, pg[g,s,t] - (t==1 ? Pg_t0[g] : pg[g,s,t-1]) + spin_10[g,s,t] + spin_30[g,s,t] <= ramp_up[g]*ug[g,t] + pg_lim[g].max*vg[g,t])
        @constraint(model, (t==1 ? Pg_t0[g] : pg[g,s,t-1]) - pg[g,s,t]  <= ramp_dn[g]*ug[g,t] + pg_lim[g].max*wg[g,t])
        @constraint(model, spin_10[g,s,t] <= ramp_up[g]*ug[g,t]/6)
        @constraint(model, spin_10[g,s,t] + spin_30[g,s,t] <= ramp_up[g]*ug[g,t]/2)
        @constraint(model, Nspin_10[g,s,t] <= ramp_up[g]*(1-ug[g,t])/6)
        @constraint(model, Nspin_10[g,s,t] + Nspin_30[g,s,t] <= ramp_up[g]*(1-ug[g,t])/2)
        @constraint(model, spin_10[g,s,t] + spin_30[g,s,t] <= (pg_lim[g].max - pg_lim[g].min)*ug[g,t])
        @constraint(model, Nspin_10[g,s,t] + Nspin_30[g,s,t] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g,t]))
    end

    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(pg[g,s,t] for g in thermal_gen_names), 1.0)
    end

    # Up and down time constraints
    history_vg = model[:init_value].history_vg
    history_wg = model[:init_value].history_wg
    time_up_t0 = Dict(g => ug_t0[g] * get_time_at_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    time_down_t0 = Dict(g => (1 - ug_t0[g])*get_time_at_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    lhs_on = _init(model, :lhs_on)
    lhs_off = _init(model, :lhs_off)
    for g in thermal_gen_names, t in time_steps
        time_limits = get_time_limits(get_component(ThermalGen, sys, g))
        prev_len = length(history_vg[g])
        lhs_on[g,t] = AffExpr()
        lhs_off[g,t] = AffExpr()

        if t - time_limits[:up] >= 0
            lhs_on[g,t] += sum(vg[g,i] for i in UnitRange{Int}(Int(t - time_limits[:up] + 1), t))
        else
            if prev_len >= ceil(Int, time_limits[:up]-t)  
                lhs_on[g,t] += sum(vg[g,i] for i in UnitRange{Int}(1, t))
                lhs_on[g,t] += sum(history_vg[g][end-i] for i in UnitRange{Int}(0, ceil(Int, time_limits[:up]-t)-1))
            # elseif t <= max(0, time_limits[:up] - time_up_t0[g]) && time_up_t0[g] > 0
                # add_to_expression!(lhs_on[g,t], 1)
            else
                lhs_on[g,t] += sum(vg[g,i] for i in 1:t) + sum(history_vg[g])
            end
        end
        
        if t-time_limits[:down] >= 0
            lhs_off[g,t] += sum(wg[g,i] for i in UnitRange{Int}(Int(t-time_limits[:down]+1), t); init = 0)
        else
            if prev_len >= ceil(Int, time_limits[:down]-t) 
                lhs_off[g,t] += sum(wg[g,i] for i in UnitRange{Int}(1, t))
                lhs_off[g,t] += sum(history_wg[g][end-i] for i in UnitRange{Int}(0, ceil(Int, time_limits[:down]-t)-1))
            # elseif t <= max(0, time_limits[:down] - time_down_t0[g]) && time_down_t0[g] > 0
                # add_to_expression!(lhs_off[g,t], 1)
            else
                lhs_off[g,t] += sum(wg[g,i] for i in 1:t) + sum(history_wg[g])
            end
        end
    end
    @constraint(model, eq_uptime[g in thermal_gen_names, t in time_steps], lhs_on[g,t] - ug[g,t] <= 0.0)
    @constraint(model, eq_downtime[g in thermal_gen_names, t in time_steps], lhs_off[g,t] + ug[g,t] <= 1.0)
                                                                    
    # Add variable cost to objective function
    if isa(variable_cost[thermal_gen_names[1]], Float64)
        add_to_expression!(model[:obj], sum(
                   pg[g,s,t]*variable_cost[g]
                   for g in thermal_gen_names, s in scenarios, t in time_steps), 1/length(scenarios))
    elseif isa(variable_cost[thermal_gen_names[1]], Tuple)
        add_to_expression!(model[:obj], sum(
                    pg[g,s,t]^2*variable_cost[g][1] + pg[g,s,t]*variable_cost[g][2]
                    for g in thermal_gen_names, s in scenarios, t in time_steps), 1/length(scenarios))
    else
        error("Different variable cost type other than Float64 or Tuple")
    end   
    
    # Add fixed, startup, shutdown to objective function
    add_to_expression!(model[:obj], sum(
                   ug[g,t]*fixed_cost[g] + vg[g,t]*startup_cost[g] + 
                   wg[g,t]*shutdown_cost[g] for g in thermal_gen_names, t in time_steps))

    # Enforce decsion variables for t = 1
    # @variable(model, t_pg[g in thermal_gen_names], lower_bound = 0)
    # for g in thermal_gen_names, s in scenarios
    #     @constraint(model, pg[g,s,1] == t_pg[g])
    # end
    
    return
end