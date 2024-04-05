using PowerSystems
using JSON3, Dates, HDF5, Statistics

ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO"
solar_file = joinpath(ts_dir, "solar_scenarios.h5")
wind_file = joinpath(ts_dir, "wind_scenarios.h5")
load_file = joinpath(ts_dir, "load_scenarios.h5")

thermal_gen_names = get_name.(get_components(ThermalGen, system))
renewable_gen_names = get_name.(get_components(RenewableGen, system))
load_names = get_name.(get_components(StaticLoad, system))
thermal_gens = collect(get_components(ThermalGen, system))
loads = collect(get_components(StaticLoad, system))
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


initial_time = Dates.DateTime(2018, 1, 1)
da_resolution = Dates.Hour(1)
hour_count = 8760-48+1
scenario_count = 10
base_power = PSY.get_base_power(system)

hour_ahead_forecast = Dict{Dates.DateTime, Matrix{Float64}}()
for ix in 1:hour_count
    curr_time = initial_time + Hour(ix - 1)
    forecast = h5open(solar_file, "r") do file
        return read(file, string(curr_time))
    end
    forecast[1, :] .= mean(forecast[1, :])
    hour_ahead_forecast[curr_time] = forecast./base_power
end

scenario_forecast_data = Scenarios(
    name = "solar_power",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = scenario_count,
    scaling_factor_multiplier = PSY.get_base_power
)
add_time_series!(system, solar_gens, scenario_forecast_data)


hour_ahead_forecast = Dict{Dates.DateTime, Matrix{Float64}}()
for ix in 1:hour_count
    curr_time = initial_time + Hour(ix - 1)
    forecast = h5open(wind_file, "r") do file
        return read(file, string(curr_time))
    end
    forecast[1, :] .= mean(forecast[1, :])
    hour_ahead_forecast[curr_time] = forecast./base_power
end

scenario_forecast_data = Scenarios(
    name = "wind_power",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = scenario_count,
    scaling_factor_multiplier = PSY.get_base_power
)
add_time_series!(system, wind_gens, scenario_forecast_data)


hour_ahead_forecast = Dict{Dates.DateTime, Matrix{Float64}}()
for ix in 1:hour_count
    curr_time = initial_time + Hour(ix - 1)
    forecast = h5open(load_file, "r") do file
        return read(file, string(curr_time))
    end
    forecast[1, :] .= mean(forecast[1, :])
    hour_ahead_forecast[curr_time] = forecast./base_power
end

scenario_forecast_data = Scenarios(
    name = "load",
    resolution = da_resolution,
    data = hour_ahead_forecast,
    scenario_count = scenario_count,
    scaling_factor_multiplier = PSY.get_base_power
)
add_time_series!(system, loads, scenario_forecast_data)
