function _add_thermal_generators!(sys::System, model::Model, use_must_run::Bool)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps
    reserve_types = model[:param].reserve_types
    spin_reserve_types = model[:param].spin_reserve_types
    nonspin_reserve_types = model[:param].nonspin_reserve_types
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
    ramp_10 = Dict(g => get_rmp_up_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    ramp_30 = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)

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
 
    # power generation variables
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps])
    # reserve variables
    @variable(model, rg[g in thermal_gen_names, r in reserve_types, s in scenarios, t in time_steps] >= 0)

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
        @constraint(model, pg[g,s,t] + rg[g,"10S",s,t] + rg[g,"30S",s,t]  + rg[g,"60S",s,t] <= pg_lim[g].max*ug[g,t])
    end

    # ramping constraints and reserve constraints
    # Non-spinning reserve qualifications, time_limits[:up] > 1 are not eligible to provide non-spinning reserve
    non_faststart_gen_names = []
    nuclear_gen_names = []
    for g in thermal_gen_names
        generator = get_component(ThermalGen, sys, g)
        time_limits = get_time_limits(generator)
        if time_limits[:up] > 1
            push!(non_faststart_gen_names, g)
        end
        if generator.fuel == ThermalFuels.NUCLEAR
            push!(nuclear_gen_names, g)
        end
    end

    for g in non_faststart_gen_names, s in scenarios, t in time_steps, r in nonspin_reserve_types
        @constraint(model, rg[g,r,s,t] <= 0)
    end

    for g in nuclear_gen_names, s in scenarios, t in time_steps, r in reserve_types
        @constraint(model, rg[g,r,s,t] <= 0)
    end

    for g in thermal_gen_names, s in scenarios, t in time_steps
        # ramping constraints
        # @constraint(model, pg[g,s,t] - (t==1 ? Pg_t0[g] : pg[g,s,t-1]) + rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= ramp_30[g]*2*ug[g,t] + pg_lim[g].min*vg[g,t])
        @constraint(model, pg[g,s,t] - (t==1 ? Pg_t0[g] : pg[g,s,t-1]) <= ramp_30[g]*2*ug[g,t] + pg_lim[g].min*vg[g,t])
        @constraint(model, (t==1 ? Pg_t0[g] : pg[g,s,t-1]) - pg[g,s,t]  <= ramp_30[g]*2*ug[g,t] + pg_lim[g].max*wg[g,t])
        # reserve constraints
        @constraint(model, rg[g,"10S",s,t] <= ramp_10[g]*ug[g,t])
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] <= ramp_30[g]*ug[g,t])
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= 2*ramp_30[g]*ug[g,t])
        @constraint(model, rg[g,"10N",s,t] <= ramp_10[g]*(1-ug[g,t]))
        @constraint(model, rg[g,"10N",s,t] + rg[g,"30N",s,t] <= ramp_30[g]*(1-ug[g,t]))
        @constraint(model, rg[g,"10N",s,t] + rg[g,"30N",s,t] + rg[g,"60N",s,t] <= 2*ramp_30[g]*(1-ug[g,t]))
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= (pg_lim[g].max - pg_lim[g].min)*ug[g,t])
        @constraint(model, rg[g,"10N",s,t] + rg[g,"30N",s,t] + rg[g,"60N",s,t] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g,t]))
    end

    for s in scenarios, t in time_steps
        for g in thermal_gen_names
            add_to_expression!(expr_net_injection[s,t], pg[g,s,t], 1.0)
        end
    end

    # Up and down time constraints
    history_vg = model[:init_value].history_vg
    history_wg = model[:init_value].history_wg
    lhs_on = _init(model, :lhs_on)
    lhs_off = _init(model, :lhs_off)
    for g in thermal_gen_names, t in time_steps
        time_limits = get_time_limits(get_component(ThermalGen, sys, g))
        lhs_on[g,t] = AffExpr(0)
        lhs_off[g,t] = AffExpr(0)
        cnt = 0
        while cnt < time_limits[:up]
            if t - cnt >= 1
                add_to_expression!(lhs_on[g,t], vg[g,t-cnt], 1.0)
            elseif length(history_vg[g]) - cnt + t >= 1    
                add_to_expression!(lhs_on[g,t], history_vg[g][end-cnt+t], 1.0)
            else
                break
            end
            cnt += 1
        end
        cnt = 0
        while cnt < time_limits[:down]
            if t - cnt >= 1
                add_to_expression!(lhs_off[g,t], wg[g,t-cnt], 1.0)
            elseif length(history_wg[g]) - cnt + t >= 1
                add_to_expression!(lhs_off[g,t], history_wg[g][end-cnt+t], 1.0)
            else
                break
            end
            cnt += 1
        end
    end
    @constraint(model, eq_uptime[g in thermal_gen_names, t in time_steps], lhs_on[g,t] - ug[g,t] <= 0.0)
    @constraint(model, eq_downtime[g in thermal_gen_names, t in time_steps], lhs_off[g,t] + ug[g,t] <= 1.0)
                                                                    
    # Add variable cost to objective function
    @assert isa(variable_cost[thermal_gen_names[1]], Float64)
    for g in thermal_gen_names, s in scenarios, t in time_steps
        add_to_expression!(model[:obj], pg[g,s,t]*variable_cost[g], 1/length(scenarios))
    end
    # Add fixed, startup, shutdown to objective function
    for g in thermal_gen_names, t in time_steps
        add_to_expression!(model[:obj], ug[g,t]*fixed_cost[g] + vg[g,t]*startup_cost[g] + 
                       wg[g,t]*shutdown_cost[g])

    # if isa(variable_cost[thermal_gen_names[1]], Float64) # constant variable cost
    #     add_to_expression!(model[:obj], sum(
    #                pg[g,s,t]*variable_cost[g]
    #                for g in thermal_gen_names, s in scenarios, t in time_steps), 1/length(scenarios))
    # elseif isa(variable_cost[thermal_gen_names[1]], Tuple) # quadratic variable cost
    #     add_to_expression!(model[:obj], sum(
    #                 pg[g,s,t]^2*variable_cost[g][1] + pg[g,s,t]*variable_cost[g][2]
    #                 for g in thermal_gen_names, s in scenarios, t in time_steps), 1/length(scenarios))
    # else # others, need to be implemented
    #     error("Different variable cost type other than Float64 or Tuple")
    # end   
    
    return
end