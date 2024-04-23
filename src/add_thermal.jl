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
    @variable(model, ug[g in thermal_gen_names, t in time_steps], binary = true)
    @variable(model, vg[g in thermal_gen_names, t in time_steps], lower_bound = 0, upper_bound = 1)
    @variable(model, wg[g in thermal_gen_names, t in time_steps], lower_bound = 0, upper_bound = 1)
 
    # power generation variables
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps])
    # reserve variables
    @variable(model, spin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, Nspin_10[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, spin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    @variable(model, Nspin_30[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)

    # if ThermalGen == ThermalGen
    #     segprod = _init(model, :segprod)
    #     eq_segprod_limit = _init(model, :eq_segprod_limit)
    #     for g in thermal_gen_names
    #         K = length(variable_cost[g])
    #         for k in 1:K
    #             segprod[g,t,k] = @variable(model, lower_bound = 0, upper_bound = variable_cost[g][k][1]*ug[g,t])
    #             eq_segprod_limit[g,t,k] = @constraint(model, segprod[g,t,k] <= variable_cost[g][k][1]*ug[g,t])
    #             add_to_expression!(model[:obj], segprod[g,t,k], variable_cost[g][k][2])
    #         end
    #         @constraint(model, pg[g,t] == sum(segprod[g,t,k] for k in 1:K))
    #     end
    # end

    # Commitment status constraints
    for g in thermal_gen_names, t in time_steps
        if t == 1
            @constraint(model, ug[g,1] - ug_t0[g][1] == vg[g,1] - wg[g,1])
        else
            @constraint(model, ug[g,t] - ug[g,t-1] == vg[g,t] - wg[g,t])
        end
    end

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
        if t == 1
            @constraint(model, pg[g,s,1] - Pg_t0[g] + spin_10[g,s,1] + spin_30[g,s,1] <= ramp_up[g]*ug[g,1])
            @constraint(model, Pg_t0[g] - pg[g,s,1]  <= ramp_dn[g]*ug[g,1])
        else
            @constraint(model, pg[g,s,t] - pg[g,s,t-1] + spin_10[g,s,t] + spin_30[g,s,t] <= ramp_up[g]*ug[g,t])
            @constraint(model, pg[g,s,t-1] - pg[g,s,t] <= ramp_dn[g]*ug[g,t])
        end
        @constraint(model, spin_10[g,s,1] <= ramp_up[g]*ug[g,t]/6)
        @constraint(model, spin_10[g,s,1] + spin_30[g,s,1] <= ramp_up[g]*ug[g,t]/2)
        @constraint(model, Nspin_10[g,s,1] <= ramp_up[g]*(1-ug[g,t])/6)
        @constraint(model, Nspin_10[g,s,1] + Nspin_30[g,s,1] <= ramp_up[g]*(1-ug[g,t])/2)
        @constraint(model, spin_10[g,s,1] + spin_30[g,s,1] <= (pg_lim[g].max - pg_lim[g].min)*ug[g,t])
        @constraint(model, Nspin_10[g,s,1] + Nspin_30[g,s,1] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g,t]))
    end

    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(pg[g,s,t] for g in thermal_gen_names), 1.0)
    end

    # Up and down time constraints
    history_vg = model[:init_value].history_vg
    history_wg = model[:init_value].history_wg
    time_up_t0 = Dict(g => ug_t0[g][1] * get_time_at_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    time_down_t0 = Dict(g => (1 - ug_t0[g][1])*get_time_at_status(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    eq_uptime = _init(model, :eq_uptime)
    eq_downtime = _init(model, :eq_downtime)
    for g in thermal_gen_names, t in time_steps
        time_limits = get_time_limits(get_component(ThermalGen, sys, g))
        prev_len = length(history_vg[g])
        lhs_on = AffExpr(0)

        if t - time_limits[:up] + 1 >= 1
            for i in UnitRange{Int}(Int(t - time_limits[:up] + 1), t)
                add_to_expression!(lhs_on, vg[g,i])
            end
        else
            if prev_len >= floor(Int, time_limits[:up]-t) + 1 
                for i in UnitRange{Int}(1, t)
                    add_to_expression!(lhs_on, vg[g,i])
                end
                for i in UnitRange{Int}(0, floor(Int, time_limits[:up]-t))
                    add_to_expression!(lhs_on, history_vg[g][end-i])
                end
            elseif t <= max(0, time_limits[:up] - time_up_t0[g]) && time_up_t0[g] > 0
                add_to_expression!(lhs_on, 1)
            else
                continue
            end
        end
        eq_uptime[g,t] = @constraint(model, lhs_on - ug[g,t] <= 0.0)

        lhs_off = AffExpr(0)
        if t - time_limits[:down] + 1 >= 1
            for i in UnitRange{Int}(Int(t - time_limits[:down] + 1), t)
                add_to_expression!(lhs_off, vg[g,i])
            end
        else
            if prev_len >= floor(Int, time_limits[:down]-t) + 1 
                for i in UnitRange{Int}(1, t)
                    add_to_expression!(lhs_off, wg[g,i])
                end
                for i in UnitRange{Int}(0, floor(Int, time_limits[:down]-t))
                    add_to_expression!(lhs_off, history_wg[g][end-i])
                end
            elseif t <= max(0, time_limits[:down] - time_down_t0[g]) && time_down_t0[g] > 0
                add_to_expression!(lhs_off, 1)
            else
                continue
            end
        end
        eq_downtime[g,t] = @constraint(model, lhs_off + ug[g,t] <= 1.0)

    end

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