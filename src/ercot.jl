using PowerSystems, JuMP
using InfrastructureSystems
const IS = InfrastructureSystems

file_path = "/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/"
system = System(file_path*"DA_sys_31_scenarios.json", assign_new_uuids = true)

# clear existing time series
clear_time_series!(system)

loads = collect(get_components(PowerLoad, system))
renewables = collect(get_components(RenewableGen, system))

# Keep only one load and one wind and one solar generator
for component in collect(get_components(RenewableDispatch, system))
    remove_component!(system, component)
end
for component in collect(get_components(PowerLoad, system))
    remove_component!(system, component)
end
@assert renewables[1].prime_mover_type == PrimeMovers.WT
add_component!(system, renewables[1])
@assert renewables[2].prime_mover_type == PrimeMovers.PVe
add_component!(system, renewables[2])
add_component!(system, loads[1])

wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe,RenewableGen, system)

# add time series
ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot"
solar_file = joinpath(ts_dir, "solar_scenarios.h5")
wind_file = joinpath(ts_dir, "wind_scenarios.h5")
load_file = joinpath(ts_dir, "load_scenarios.h5")

initial_time = Dates.Date(2018, 1, 1)
da_interval = Dates.Hour(24)
da_resolution = Dates.Hour(1)
day_count = 365
hour_ahead_forecast = Dict{Dates.DateTime, Matrix{Float64}}()

for ix in 1:day_count
    curr_time = initial_time + Day(ix - 1)
    forecast = h5open(solar_file, "r") do file
        return read(file, string(curr_time))
    end
    hour_ahead_forecast[curr_time] = forecast./100.0
end

scenario_forecast_data = Scenarios(
    name = "solar_power",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = 10
)
add_time_series!(system, solar_gens, scenario_forecast_data)


for ix in 1:day_count
    curr_time = initial_time + Day(ix - 1)
    forecast = h5open(wind_file, "r") do file
        return read(file, string(curr_time))
    end
    hour_ahead_forecast[curr_time] = forecast./100.0
end

scenario_forecast_data = Scenarios(
    name = "wind_power",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = 10
)
add_time_series!(system, wind_gens, scenario_forecast_data)


for ix in 1:day_count
    curr_time = initial_time + Day(ix - 1)
    forecast = h5open(load_file, "r") do file
        return read(file, string(curr_time))
    end
    hour_ahead_forecast[curr_time] = forecast./100.0
end

scenario_forecast_data = Scenarios(
    name = "load",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = 10
)
add_time_series!(system, collect(get_components(PowerLoad, system)), scenario_forecast_data)



# thermal_gen_names = get_name.(get_components(ThermalGen, system))
# renewable_gen_names = get_name.(get_components(RenewableGen, system))
# load_names = get_name.(get_components(PowerLoad, system))
thermal_gens = collect(get_components(ThermalGen, system))
# loads = collect(get_components(PowerLoad, system))
# renewables = collect(get_components(RenewableGen, system))


# clear_components!(system)
# remove_component!(system, renewables[2])
# op_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(RenewableDispatch, system, g)))) for g in get_name.(wind_gens))
# no_load_cost = Dict(g => get_fixed(get_operation_cost(get_component(RenewableDispatch, system, g))) for g in get_name.(wind_gens))
# shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
# startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
# pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, system, g)) for g in thermal_gen_names)


