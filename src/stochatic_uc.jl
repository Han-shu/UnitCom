using DataStructures, JuMP, Dates, PowerSystems
using HiGHS

include("structs.jl")
include("add_renewables.jl")
include("storage_equations.jl")
include("system_equations.jl")

function _init(model::JuMP.Model, key::Symbol)::OrderedDict
    if !(key in keys(object_dictionary(model)))
        model[key] = OrderedDict()
    end
    return model[key]
end

function stochastic_uc(
    sys::System, optimizer; 
    start_time = Dates.Date(2018,1,1), horizon = 24, 
    VOLL=5000, use_must_run=false
    )

    has_storage = false
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    time_steps = 1:horizon
    scenarios = 1:10
    parameters = _construct_model_parameters(horizon, scenarios, start_time, VOLL = VOLL)
    model[:param] = parameters

    
    # -----------------------------------------------------------------------------------------
    # Thermal Generator
    # -----------------------------------------------------------------------------------------
    # get the struct type of thermal generator
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

    
    # Storage
    if length(get_components(GenericBattery, sys)) != 0 || length(get_components(BatteryEMS, sys)) != 0
        has_storage = true
        apply_stroage!(sys::System, model::JuMP.Model, time_steps)   
    end

    _add_renewables!(model, sys)

    _add_power_balance_eq!(model)

    add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                   pg[g,s,t]^2*variable_cost[g][2][1] + pg[g,s,t]*variable_cost[g][2][2]
                   for g in thermal_gen_names, s in scenarios, t in time_steps))
    
    add_to_expression!(model[:obj], sum(
                   ug[g,t]*fixed_cost[g] + 
                   vg[g,t]*startup_cost[g] + 
                   wg[g,t]*shutdown_cost[g]
                   for g in thermal_gen_names, t in time_steps))

    add_to_expression!(model[:obj], (1/length(scenarios))*VOLL*sum(curtailment[s,t] for s in scenarios, t in time_steps))

    @objective(model, Min, model[:obj])
    optimize!(model)
    return model  
end

model = stochastic_uc(system, HiGHS.Optimizer, start_time = DateTime(Date(2018, 7, 18)))

# start_time = DateTime(Date(2018, 7, 18))
# time_steps = 1:24   
# wind_gen = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
# total_wind = Dict(get_name(g) => 
#         get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_steps))
#         for g in wind_gens)

# startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(thermal_type, system, g))) for g in thermal_gen_names)
# shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(thermal_type, system, g))) for g in thermal_gen_names)

# new_startup_cost = Dict()
# for g in thermal_gen_names
#     new_startup_cost[g] = sum(startup_cost[g])/length(startup_cost[g])
# end

# op_cost_types = Set()
# for g in 1:length(thermal_gen_names)
#     println(g)
#     println(typeof(thermal_gens[g].operation_cost))
#     push!(op_cost_types, string(typeof(thermal_gens[g].operation_cost)))
# end

# thermal_type = first(gen_type)
# get_components(ThermalGen, system)

# thermal_type == ThermalStandard
# thermal_type == ThermalMultiStart

# variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(thermal_type, system, g)))) for g in thermal_gen_names)

# length(variable_cost["DEER_PARK_ENERGY_CENTER_CC4"])