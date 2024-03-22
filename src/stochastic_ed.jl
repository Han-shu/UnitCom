function ed_model(sys::System, optimizer; VOLL = 1000, start_time = DateTime(Date(2018, 1, 1)))
    model = Model(optimizer)
    model[:obj] = QuadExpr()
    time_periods = 1:24
    scenarios = 1:10

    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    bid_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, system)
    @variable(model, pg[g in thermal_gen_names, s in scenarios, t in time_periods] >= 0)
    @variable(model, curtailment[s in scenarios, t in time_periods] )

    for g in get_components(ThermalGen, sys), s in scenarios, t in time_periods
        name = get_name(g)
        @constraint(model, pg[name,s,t] >= get_active_power_limits(g).min)
        @constraint(model, pg[name,s,t] <= get_active_power_limits(g).max)
    end

    net_load = zeros(length(time_periods), length(scenarios))
    for g in solar_gens
        net_load -= get_time_series_values(Scenarios, g, "solar_power", start_time = start_time, len = length(time_periods))
    end

    for g in wind_gens
        net_load -= get_time_series_values(Scenarios, g, "wind_power", start_time = start_time, len = length(time_periods))
    end

    for load in get_components(PowerLoad, sys)
        net_load += get_time_series_values(Scenarios, load, "load", start_time = start_time, len = length(time_periods))
    end
    
    for s in scenarios, t in time_periods
        @constraint(model, sum(pg[g,s,t] for g in thermal_gen_names) + curtailment[s,t] == net_load[t,s])
    end 

    add_to_expression!(model[:obj], (1/length(scenarios))*sum(
                   pg[g,s,t]^2*bid_cost[g][1][1] + pg[g,s,t]*bid_cost[g][1][2]
                   for g in thermal_gen_names, s in scenarios, t in time_periods))

    add_to_expression!(model[:obj], (1/length(scenarios))*VOLL*sum(curtailment[s,t] for s in scenarios, t in time_periods))

    @objective(model, Min, model[:obj])

    optimize!(model)
    return model
end

model = ed_model(system, HiGHS.Optimizer, start_time = DateTime(Date(2018, 7, 18)))

value(model[:curtailment][10,1])

value(model[:pg]["Solitude", 1, 1])



# gen1 = get_component(ThermalGen, system, "Solitude")
# PowerSystems.get_active_power(gen1)
counts = get_time_series_counts(system)
get_time_series_resolution(system)
has_time_series(loads[1])
has_time_series(loads[1], StaticTimeSeries)
has_time_series(loads[1], Scenarios)
has_time_series(loads[1], Deterministic)
get_time_series_container(loads[1])

get_time_series_array(Scenarios, loads[1], "load", start_time = DateTime("2018-01-06T00:00:00"), len = 48)

get_time_series_values(Scenarios, loads[1], "load", start_time = DateTime("2018-01-06T00:00:00"), len = 48)

get_time_series_array(Scenarios, renewables[1], "solar_power", start_time = DateTime("2018-01-06T00:00:00"), len = 48)
get_time_series_array(Scenarios, renewables[2], "wind_power", start_time = DateTime("2018-01-06T00:00:00"), len = 48)

get_max_active_power(thermal_gens[3])
get_base_power(system)

PSI.get_active_power_limits(thermal_gens[3])

op_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, system, g)))) for g in thermal_gen_names)
no_load_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, system, g)) for g in thermal_gen_names)

get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
ramp_up = Dict(g => get_rmp_up_limit(get_component(ThermalGen, system, g))*60 for g in thermal_gen_names)
ramp_dn = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, system, g))*60 for g in thermal_gen_names)

ug_t0 = Dict(g => PSY.get_status(get_component(ThermalGen, system, g)) for g in thermal_gen_names)
Pg_t0 = Dict(g => PSY.get_active_power(get_component(ThermalGen, system, g)) for g in thermal_gen_names)
variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, system, g)))) for g in thermal_gen_names)
must_run_gen_names = get_name.(get_components(x -> PSY.get_must_run(x), ThermalGen, system))

wind_gen_names = get_name.(wind_gens)

variable_cost2 = Dict(g => get_variable(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)


fuel = Dict(g => get_fuel(get_component(ThermalGen, system, g)) for g in thermal_gen_names)

get_power_trajectory(get_component(ThermalGen, system, "Solitude"))


file_path = "/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/"
system31 = System(file_path*"DA_sys_31_scenarios.json")
reserve1 = collect(get_components(VariableReserve, system31))
reserve3 = collect(get_components(VariableReserveNonSpinning, system31))

has_time_series(reserve1[1])
get_time_series_container(reserve1[1])
REG_DN = get_time_series(Deterministic, reserve1[1], "requirement")
REG_DN[DateTime("2018-01-01T00:00:00")]

for key in keys(REG_DN)
    println(key, " ", REG_DN[key])
    break
end
REG_DN.data[DateTime("2018-01-01T00:00:00")]