using PowerSystems, Dates, HDF5, Statistics

function _construct_fcst_data(file::AbstractString, base_power::Float64, initial_time::DateTime)::Dict{Dates.DateTime, Matrix{Float64}}
    data = Dict{Dates.DateTime, Matrix{Float64}}()
    for ix in 1:8713
        curr_time = initial_time + Hour(ix - 1)
        forecast = h5open(file, "r") do file
            return read(file, string(curr_time))
        end
        forecast[1, :] .= mean(forecast[1, :])
        forecast = max.(forecast, 0)
        data[curr_time] = forecast./base_power
    end
    return data
end

function add_scenarios_time_series!(system::System)::Nothing
    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO"
    solar_file = joinpath(ts_dir, "solar_scenarios.h5")
    wind_file = joinpath(ts_dir, "wind_scenarios.h5")
    load_file = joinpath(ts_dir, "load_scenarios.h5")

    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    initial_time = Dates.DateTime(2019, 1, 1)
    da_resolution = Dates.Hour(1)
    scenario_count = 10
    base_power = PSY.get_base_power(system)

    solar_data = _construct_fcst_data(solar_file, base_power, initial_time)
    scenario_forecast_data = Scenarios(
        name = "solar_power",
        resolution = da_resolution,
        data = solar_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, solar_gens, scenario_forecast_data)


    wind_data = _construct_fcst_data(wind_file, base_power, initial_time)
    scenario_forecast_data = Scenarios(
        name = "wind_power",
        resolution = da_resolution,
        data = wind_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, wind_gens, scenario_forecast_data)

    load_data = _construct_fcst_data(load_file, base_power, initial_time)
    scenario_forecast_data = Scenarios(
        name = "load",
        resolution = da_resolution,
        data = load_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, loads, scenario_forecast_data)
return nothing
end