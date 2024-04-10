using PowerSystems, JuMP
using InfrastructureSystems
const IS = InfrastructureSystems

file_path = "/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/"
system = System(file_path*"DA_sys_31_scenarios.json", assign_new_uuids = true)

base_power = get_base_power(system)
thermal_gen_names = get_name.(get_components(ThermalGen, system))
op_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, system, g)))) for g in thermal_gen_names)
no_load_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
# startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, system, g))) for g in thermal_gen_names)
startup_cost_hot = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, system, g)))[:hot] for g in thermal_gen_names)
startup_cost_warm = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, system, g)))[:warm] for g in thermal_gen_names)
startup_cost_cold = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, system, g)))[:cold] for g in thermal_gen_names)
pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, system, g)) for g in thermal_gen_names)
fuel = Dict(g => get_fuel(get_component(ThermalGen, system, g)) for g in thermal_gen_names)
pm = Dict(g => get_prime_mover_type(get_component(ThermalGen, system, g)) for g in thermal_gen_names)

df = DataFrame(
    name = thermal_gen_names,
    no_load_cost = [no_load_cost[g] for g in thermal_gen_names],
    shutdown_cost = [shutdown_cost[g] for g in thermal_gen_names],
    startup_cost_hot = [startup_cost_hot[g] for g in thermal_gen_names],
    startup_cost_warm = [startup_cost_warm[g] for g in thermal_gen_names],
    startup_cost_cold = [startup_cost_cold[g] for g in thermal_gen_names],
    pg_min = [pg_lim[g][:min]*base_power for g in thermal_gen_names],
    pg_max = [pg_lim[g][:max]*base_power for g in thermal_gen_names],
    fuel = [fuel[g] for g in thermal_gen_names],
    pm = [pm[g] for g in thermal_gen_names],
    op_cost = [op_cost[g] for g in thermal_gen_names],
)
CSV.write(file_path*"thermal_gen_info.csv", df)




# clear existing time series
clear_time_series!(system)

loads = collect(get_components(StaticLoad, system))
renewables = collect(get_components(RenewableGen, system))

# Keep only one load and one wind and one solar generator
for component in collect(get_components(RenewableDispatch, system))
    remove_component!(system, component)
end
for component in collect(get_components(StaticLoad, system))
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

initial_time = Dates.Date(2019, 1, 1)
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
add_time_series!(system, collect(get_components(StaticLoad, system)), scenario_forecast_data)



# thermal_gen_names = get_name.(get_components(ThermalGen, system))
# renewable_gen_names = get_name.(get_components(RenewableGen, system))
# load_names = get_name.(get_components(StaticLoad, system))
thermal_gens = collect(get_components(ThermalGen, system))
# loads = collect(get_components(StaticLoad, system))
# renewables = collect(get_components(RenewableGen, system))


# clear_components!(system)
# remove_component!(system, renewables[2])


