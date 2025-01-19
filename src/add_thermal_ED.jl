function _add_thermal_generators_ED!(sys::System, model::JuMP.Model)
    time_steps = model[:param].time_steps
    scenarios = model[:param].scenarios
    horizon = length(time_steps)
    reserve_types = model[:param].reserve_types
    spin_reserve_types = model[:param].spin_reserve_types
    min_step = minute(model[:param].start_time)/5
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))

    # initial value
    init_value = nothing
    if !haskey(model, :init_value)
        ug = Dict(g => [1, 1, 1] for g in thermal_gen_names) # Assume all thermal generators are on
        vg = Dict(g => [0, 0, 0] for g in thermal_gen_names) # Assume all thermal generators are started up before
        wg = Dict(g => [0, 0, 0] for g in thermal_gen_names)
        Pg_t0 = Dict(g => get_active_power(get_component(ThermalGen, sys, g)) for g in thermal_gen_names) # all 0
    else
        init_value = model[:init_value]
        ug = init_value.ug_t0 # commitment status, 2-element Vector, 1 for on, 0 for off
        vg = init_value.vg_t0 # startup status, 2-element Vector
        wg = init_value.wg_t0 # shutdown status, 2-element Vector
        Pg_t0 = init_value.Pg_t0
    end
        
    vg_min5 = Dict(g => zeros(horizon) for g in thermal_gen_names)
    wg_min5 = Dict(g => zeros(horizon) for g in thermal_gen_names)


    for t in time_steps
        i = Int(div(min_step+t-1, 12)+1) # determine the hourly status index
        if minute(model[:param].start_time + Minute(5)*(t-1)) == 0
            for g in thermal_gen_names
                vg_min5[g][t] = vg[g][i]
                wg_min5[g][t] = wg[g][i]
            end
        end
    end

    # Thermal generators
    pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_steps])
    @variable(model, rg[g in thermal_gen_names, r in reserve_types, s in scenarios, t in time_steps] >= 0)

    must_run_gen_names = get_name.(get_components(x -> PSY.get_must_run(x), ThermalGen, sys))

    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1) # determine the commitment status index
        if isnothing(init_value)
            if g in must_run_gen_names
                @constraint(model, pg[g,s,t] >= pg_lim[g].min)
            else
                @constraint(model, pg[g,s,t] >= 0)
            end
        else
            @constraint(model, pg[g,s,t] >= pg_lim[g].min*ug[g][i])
        end
        @constraint(model, pg[g,s,t] + rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= pg_lim[g].max*ug[g][i])
    end

    # ramping constraints and reserve constraints
    
    # Non-spinning reserve qualifications, time_limits[:up] > 1 are not eligible to provide non-spinning reserve
    # Nuclear generators are not eligible to provide reserve
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

    get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
    get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
    ramp_10 = Dict(g => get_rmp_up_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    ramp_30 = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    if !isnothing(init_value)
        for g in thermal_gen_names, s in scenarios, t in time_steps
            i = Int(div(min_step+t-1, 12)+1) # determine the commitment status index
            @constraint(model, pg[g,s,t] - (t==1 ? Pg_t0[g] : pg[g,s,t-1]) <= ramp_10[g]*ug[g][i]/2 + pg_lim[g].min*vg_min5[g][t])
            @constraint(model, (t==1 ? Pg_t0[g] : pg[g,s,t-1]) - pg[g,s,t] <= ramp_10[g]*ug[g][i]/2 + pg_lim[g].max*wg_min5[g][t])
        end
    end

    for g in thermal_gen_names, s in scenarios, t in time_steps
        i = Int(div(min_step+t-1, 12)+1)
        @constraint(model, rg[g,"10S",s,t]<= ramp_10[g]*ug[g][i])
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] <= ramp_30[g]*ug[g][i])
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= 2*ramp_30[g]*ug[g][i])
        @constraint(model, rg[g,"10N",s,t]<= ramp_10[g]*(1-ug[g][i]))
        @constraint(model, rg[g,"10N",s,t]+ rg[g,"30N",s,t] <= ramp_30[g]*(1-ug[g][i]))
        @constraint(model, rg[g,"10N",s,t]+ rg[g,"30N",s,t] + rg[g,"60S",s,t] <= 2*ramp_30[g]*(1-ug[g][i]))
        @constraint(model, rg[g,"10S",s,t] + rg[g,"30S",s,t] + rg[g,"60S",s,t] <= (pg_lim[g].max - pg_lim[g].min)*ug[g][i])
        @constraint(model, rg[g,"10N",s,t]+ rg[g,"30N",s,t] + rg[g,"60N",s,t] <= (pg_lim[g].max - pg_lim[g].min)*(1-ug[g][i]))
    end

    for g in thermal_gen_names, s in scenarios, t in time_steps
        add_to_expression!(model[:expr_net_injection][s,t], pg[g,s,t], 1.0)
    end

    @assert isa(variable_cost[thermal_gen_names[1]], Float64)
    for g in thermal_gen_names, s in scenarios, t in time_steps
        add_to_expression!(model[:obj], pg[g,s,t]*variable_cost[g], 1/length(scenarios))
    end

    return 
end