function _add_thermal_generators!(model::JuMP.Model, sys::System, use_must_run::Bool)::Nothing
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps

    expr_net_injection = model[:expr_net_injection]

    # get the struct type of thermal generator: ThermalStandard or ThermalMultiStart
    thermal_struct_type = Set()
    for g in get_components(ThermalGen, system)
        push!(thermal_struct_type, typeof(g))
    end
    @assert length(thermal_struct_type) == 1
    thermal_type = first(thermal_struct_type)

    thermal_gen_names = get_name.(get_components(thermal_type, sys))
    pg_lim = Dict(g => get_active_power_limits(get_component(thermal_type, sys, g)) for g in thermal_gen_names)
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(thermal_type, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(thermal_type, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(thermal_type, sys, g)))) for g in thermal_gen_names)

    if thermal_type == ThermalMultiStart
        # use the average of hot/warm/cold startup cost
        #TODO 
        categories_startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalMultiStart, sys, g))) for g in thermal_gen_names)
        startup_cost = Dict(g => sum(categories_startup_cost[g])/length(categories_startup_cost[g]) for g in thermal_gen_names)
    else
        startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    end

    get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
    get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
    ramp_up = Dict(g => get_rmp_up_limit(get_component(thermal_type, sys, g))*60 for g in thermal_gen_names)
    ramp_dn = Dict(g => get_rmp_dn_limit(get_component(thermal_type, sys, g))*60 for g in thermal_gen_names)

    # initial condition
    ug_t0 = Dict(g => PSY.get_status(get_component(thermal_type, sys, g)) for g in thermal_gen_names)
    Pg_t0 = Dict(g => PSY.get_active_power(get_component(thermal_type, sys, g)) for g in thermal_gen_names)

    if use_must_run
        must_run_gen_names = get_name.(get_components(x -> PSY.get_must_run(x), thermal_type, sys))
    end

    # -----------------------------------------------------------------------------------------  
    # Variables 
    # -----------------------------------------------------------------------------------------
    # commitment variables
    @variable(model, ug[g in thermal_gen_names, t in time_steps], binary = true)
    # startup variables
    @variable(model, 0 <= vg[g in thermal_gen_names, t in time_steps] <= 1)
    # shutdown variables
    @variable(model, 0 <= wg[g in thermal_gen_names, t in time_steps] <= 1)
    # power generation variables
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps] >= 0)
    if thermal_type == ThermalMultiStart
        segprod = _init(model, :segprod)
        eq_segprod_limit = _init(model, :eq_segprod_limit)
        for g in thermal_gen_names
            K = length(variable_cost[g])
            for k in 1:K
                segprod[g,t,k] = @variable(model, lower_bound = 0, upper_bound = variable_cost[g][k][1]*ug[g,t])
                eq_segprod_limit[g,t,k] = @constraint(model, segprod[g,t,k] <= variable_cost[g][k][1]*ug[g,t])
                add_to_expression!(model[:obj], segprod[g,t,k], variable_cost[g][k][2])
            end
            @constraint(model, pg[g,t] == sum(segprod[g,t,k] for k in 1:K))
        end
    end

    # -----------------------------------------------------------------------------------------  
    # Constraints 
    # -----------------------------------------------------------------------------------------
    # Commitment status constraints
    for g in thermal_gen_names, t in time_steps
        if t == 1
            @constraint(model, ug[g,1] - ug_t0[g] == vg[g,1] - wg[g,1])
        else
            @constraint(model, ug[g,t] - ug[g,t-1] == vg[g,t] - wg[g,t])
        end
    end

    if use_must_run
        for g in must_run_gen_names, t in time_steps
            JuMP.fix(ug[g,t], 1.0; force = true)
        end
    end

    # energy dispatch constraints 
    for g in thermal_gen_names, s in scenarios, t in time_steps
        @constraint(model, pg[g,s,t] >= pg_lim[g].min*ug[g,t])
        @constraint(model, pg[g,s,t] <= pg_lim[g].max*ug[g,t])
    end

    # ramping constraints
    for g in thermal_gen_names, s in scenarios, t in time_steps
        if t == 1
            @constraint(model, pg[g,s,1] - ug_t0[g]*(Pg_t0[g] - pg_lim[g].min) <= ramp_up[g])
            @constraint(model, ug_t0[g]*(Pg_t0[g] - pg_lim[g].min) - pg[g,s,1]  <= ramp_dn[g])
        else
            @constraint(model, pg[g,s,t] - pg[g,s,t-1] <= ramp_up[g])
            @constraint(model, pg[g,s,t-1] - pg[g,s,t] <= ramp_dn[g])
        end
    end
    for s in scenarios, t in time_steps
        add_to_expression!(expr_net_injection[s,t], sum(pg[g,s,t] for g in thermal_gen_names), 1.0)
    end

    if isa(variable_cost[thermal_gen_names[1]], Tuple)
        add_to_expression!(model[:obj], sum(
                   pg[g,s,t]^2*variable_cost[g][1] + pg[g,s,t]*variable_cost[g][2]
                   for g in thermal_gen_names, s in scenarios, t in time_steps))
    else
        add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                    pg[g,s,t]^2*variable_cost[g][2][1] + pg[g,s,t]*variable_cost[g][2][2]
                    for g in thermal_gen_names, s in scenarios, t in time_steps))
    end
    
    add_to_expression!(model[:obj], sum(
                   ug[g,t]*fixed_cost[g] + vg[g,t]*startup_cost[g] + 
                   wg[g,t]*shutdown_cost[g] for g in thermal_gen_names, t in time_steps))

    return
end