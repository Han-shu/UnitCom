# Add scenarios data by ranking the total net load 

using PowerSystems, Dates, HDF5, Statistics

function _read_h5_by_idx(file, time)
    h5open(file, "r") do file
    return read(file, string(time))
end

function _construct_fcst_data_UC(base_power::Float64, initial_time::DateTime)
    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO_Hour"
    solar_file = joinpath(ts_dir, "solar_scenarios.h5")
    wind_file = joinpath(ts_dir, "wind_scenarios.h5")
    load_file = joinpath(ts_dir, "load_scenarios.h5")

    num_idx = h5open(file, "r") do file
        return length(read(file))
    end

    solar_data = Dict{Dates.DateTime, Matrix{Float64}}()
    wind_data = Dict{Dates.DateTime, Matrix{Float64}}()
    load_data = Dict{Dates.DateTime, Matrix{Float64}}()

    for ix in 1:num_idx
        curr_time = initial_time + Hour(ix - 1)
        solar_forecast = _read_h5_by_idx(solar_file, curr_time)
        wind_forecast = _read_h5_by_idx(wind_file, curr_time)

        forecast = max.(forecast, 0)
        data[curr_time] = forecast./base_power
    end
    return solar_data, wind_data, load_data
end

function _construct_fcst_data_ED(file::AbstractString, base_power::Float64, initial_time::DateTime)::Dict{Dates.DateTime, Matrix{Float64}}
    data = Dict{Dates.DateTime, Matrix{Float64}}()
    num_idx = h5open(file, "r") do file
        return length(read(file))
    end
    for ix in 1:num_idx
        curr_time = initial_time + Minute(5)*(ix-1)
        forecast = h5open(file, "r") do file
            return read(file, string(curr_time))
        end
        forecast = max.(forecast, 0)
        data[curr_time] = forecast./base_power
    end
    return data
end

function add_rank_scenarios_time_series_UC!(system::System)::Nothing

    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    initial_time = Dates.DateTime(2018, 12, 31, 20)
    da_resolution = Dates.Hour(1)
    scenario_count = 10
    base_power = PSY.get_base_power(system)

    #TODO construct data by ranking
    solar_data, wind_data, load_data = _construct_fcst_data_UC(base_power, initial_time)

    scenario_forecast_data = Scenarios(
        name = "solar_power",
        resolution = da_resolution,
        data = solar_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, solar_gens, scenario_forecast_data)


    scenario_forecast_data = Scenarios(
        name = "wind_power",
        resolution = da_resolution,
        data = wind_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, wind_gens, scenario_forecast_data)

    scenario_forecast_data = Scenarios(
        name = "load",
        resolution = da_resolution,
        data = load_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, loads, scenario_forecast_data)

    _add_time_series_hydro!(system)
return nothing
end



function add_scenarios_time_series_ED!(system::System)::Nothing
    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO_Min5"
    solar_file = joinpath(ts_dir, "solar_scenarios.h5")
    wind_file = joinpath(ts_dir, "wind_scenarios.h5")
    load_file = joinpath(ts_dir, "load_scenarios.h5")

    base_power = PSY.get_base_power(system)
    ed_init_time = Dates.DateTime(2018, 12, 31, 20)

    #TODO construct data by ranking
    solar_data = _construct_fcst_data_ED(solar_file, base_power, ed_init_time)
    wind_data = _construct_fcst_data_ED(wind_file, base_power, ed_init_time)
    load_data = _construct_fcst_data_ED(load_file, base_power, ed_init_time)
    
    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    ha_resolution = Dates.Minute(5)
    scenario_count = 10

    scenario_forecast_data = Scenarios(
        name = "solar_power",
        resolution = ha_resolution,
        data = solar_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, solar_gens, scenario_forecast_data)

    scenario_forecast_data = Scenarios(
        name = "wind_power",
        resolution = ha_resolution,
        data = wind_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, wind_gens, scenario_forecast_data)

    scenario_forecast_data = Scenarios(
        name = "load",
        resolution = ha_resolution,
        data = load_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, loads, scenario_forecast_data)

    _add_time_series_hydro!(system; min5_flag = true)
    return nothing
end




