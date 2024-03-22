using PowerSystems, Gurobi, JuMP
using PowerSystemCaseBuilder
using Dates
using TimeSeries

sys = System("/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/DA_sys_31_scenarios.json")


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


get_components(ThermalMultiStart, sys)
get_components(RenewableDispatch, sys)
thermal_gen_names = get_name.(get_components(ThermalGen, sys))
renewable_gen_names = get_name.(get_components(RenewableGen, sys))

thermal_gen_names2 = get_name.(get_components(ThermalMultiStart, sys))
renewable_gen_names2 = get_name.(get_components(RenewableDispatch, sys))


file_dir = joinpath(pkgdir(PowerSystems), "docs", "src", "tutorials", "tutorials_data")
system = System(joinpath(file_dir, "RTS_GMLC.m"));
to_json(system, "system.json")
system2 = System("system.json")


resolution = Dates.Hour(1)
data = Dict(
    DateTime("2020-01-01T00:00:00") => 10.0*ones(24),
    DateTime("2020-01-01T01:00:00") => 5.0*ones(24),
)
forecast = Deterministic("max_active_power", data, resolution)


resolution = Dates.Hour(1)
dates = range(DateTime("2020-01-01T00:00:00"), step = resolution, length = 24)
data = TimeArray(dates, ones(24))
time_series = SingleTimeSeries("max_active_power", data)


# Create static time series data.
resolution = Dates.Hour(1)
dates = range(DateTime("2020-01-01T00:00:00"), step = resolution, length = 8760)
data = TimeArray(dates, ones(8760))
ts = SingleTimeSeries("max_active_power", data)
add_time_series!(sys, component, ts)

# Transform it to Deterministic
transform_single_time_series!(sys, 24, Hour(24))


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

# FORECASTS_DIR = "/Users/hanshu/Desktop/Sienna/PowerSystemsTestData/5-Bus/5bus_ts"
# FORECASTS_DIR = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot"
# fname = joinpath(FORECASTS_DIR, "timeseries_pointers_da.json")
# open(fname, "r") do f
#     JSON3.@pretty JSON3.read(f)
# end
# add_time_series!(system, fname)