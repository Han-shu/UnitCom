using PowerSystems, PowerSimulations, HydroPowerSimulations
using JSON3, Dates, HDF5
const PSI = PowerSimulations
const PSY = PowerSystems

ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot"
solar_file = joinpath(ts_dir, "solar_scenarios.h5")
wind_file = joinpath(ts_dir, "wind_scenarios.h5")
load_file = joinpath(ts_dir, "load_scenarios.h5")

file_dir = joinpath(pkgdir(PowerSystems), "docs", "src", "tutorials", "tutorials_data")
system = System(joinpath(file_dir, "case5_re.m"), assign_new_uuids = true)

thermal_gen_names = get_name.(get_components(ThermalGen, system))
renewable_gen_names = get_name.(get_components(RenewableGen, system))
load_names = get_name.(get_components(PowerLoad, system))
thermal_gens = collect(get_components(ThermalGen, system))
loads = collect(get_components(PowerLoad, system))
renewables = collect(get_components(RenewableGen, system))

wind_gens = get_components(
            x -> x.prime_mover_type == PrimeMovers.WT,
            RenewableGen,
            system,
        )

solar_gens = get_components(
    x -> x.prime_mover_type == PrimeMovers.PVe,
    RenewableGen,
    system,
)


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
    hour_ahead_forecast[curr_time] = forecast
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
    hour_ahead_forecast[curr_time] = forecast
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
    hour_ahead_forecast[curr_time] = forecast./3
end

scenario_forecast_data = Scenarios(
    name = "load",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = 10
)
add_time_series!(system, loads, scenario_forecast_data)




