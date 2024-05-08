using PowerSystems, HDF5, Dates, Statistics

function  _read_fcst_quantiles(filename::AbstractString; issolar = false, min5_flag = false)::Matrix{Float64}
    forecast = h5open(filename, "r") do file
        return read(file)
    end
    matrix = forecast["forecasts"]
    if issolar
        matrix = hcat(matrix[:, 1:40], matrix[:, 81:end]) 
    end
    matrix = matrix[:, 2:2:end] # only take the newest forecast
    if min5_flag
        new_matrix = interpolate_matrix(matrix)
    else
        ncols = size(matrix, 2)
        div_val = Int(ncols/8760)
        new_matrix = zeros(size(matrix, 1), 8760)
        for col in 1:div_val:ncols
            new_matrix[:, cld(col, div_val)] = mean(matrix[:, col:col+div_val-1], dims=2)
        end
    end
    return transpose(new_matrix)
end


function interpolate_matrix(matrix)
    num_row = size(matrix, 1)
    num_col = size(matrix, 2)
    interpolated_matrix = zeros(num_row, 3*num_col)
    for i in 1:num_col-1
        interpolated_matrix[:, 3*(i-1)+1] = matrix[:, i]
        interpolated_matrix[:, 3*(i-1)+2] = matrix[:, i]*2/3 + matrix[:, i+1]./3
        interpolated_matrix[:, 3*(i-1)+3] = matrix[:, i]./3 + matrix[:, i+1].*2/3
    end
    interpolated_matrix[:, 3*(num_col-1)+1] = matrix[:, num_col]
    interpolated_matrix[:, 3*(num_col-1)+2] = matrix[:, num_col]
    interpolated_matrix[:, 3*(num_col-1)+3] = matrix[:, num_col]
    return interpolated_matrix
end

function _construct_fcst_data_UC(fcst_quantiles::Matrix{Float64}, base_power::Float64, initial_time::DateTime)::Dict{Dates.DateTime, Matrix{Float64}}
    data = Dict{Dates.DateTime, Matrix{Float64}}()
    for ix in 1:8713
        curr_time = initial_time + Hour(ix - 1)
        data[curr_time] = fcst_quantiles[ix:ix+47, :]./base_power
    end
    return data
end

function _construct_fcst_data_ED(fcst_quantiles::Matrix{Float64}, base_power::Float64, initial_time::DateTime)::Dict{Dates.DateTime, Matrix{Float64}}
    data = Dict{Dates.DateTime, Matrix{Float64}}()
    for ix in 1:8760*12-23
        curr_time = initial_time + (ix - 1)*Minute(5)
        data[curr_time] = fcst_quantiles[ix:ix+23, :]./base_power
    end
    return data
end

function add_quantiles_time_series_UC!(system::System)::Nothing
    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/ARPAE_NYISO"
    solar_fcst_file = joinpath(ts_dir, "BA_Existing_solar_intra-hour_fcst_2019.h5")
    wind_fcst_file = joinpath(ts_dir, "BA_Existing_wind_intra-hour_fcst_2019.h5")
    load_fcst_file = joinpath(ts_dir, "BA_load_intra-hour_fcst_2019.h5")

    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    wind_fcst_quantiles = _read_fcst_quantiles(wind_fcst_file)
    solar_fcst_quantiles = _read_fcst_quantiles(solar_fcst_file; issolar = true)
    load_fcst_quantiles = _read_fcst_quantiles(load_fcst_file)

    initial_time = Dates.DateTime(2018, 12, 31, 20)
    da_resolution = Dates.Hour(1)
    scenario_count = 99
    base_power = PSY.get_base_power(system)

    solar_data = _construct_fcst_data_UC(solar_fcst_quantiles, base_power, initial_time)
    wind_data = _construct_fcst_data_UC(wind_fcst_quantiles, base_power, initial_time)
    load_data = _construct_fcst_data_UC(load_fcst_quantiles, base_power, initial_time)

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


function add_quantiles_time_series_ED!(system::System)::Nothing
    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/ARPAE_NYISO"
    solar_fcst_file = joinpath(ts_dir, "BA_Existing_solar_intra-hour_fcst_2019.h5")
    wind_fcst_file = joinpath(ts_dir, "BA_Existing_wind_intra-hour_fcst_2019.h5")
    load_fcst_file = joinpath(ts_dir, "BA_load_intra-hour_fcst_2019.h5")
   
    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    wind_fcst_quantiles = _read_fcst_quantiles(wind_fcst_file; min5_flag = true)
    solar_fcst_quantiles = _read_fcst_quantiles(solar_fcst_file; issolar = true, min5_flag = true)
    load_fcst_quantiles = _read_fcst_quantiles(load_fcst_file; min5_flag = true)

    initial_time = Dates.DateTime(2018, 12, 31, 20)
    ha_resolution = Dates.Minute(5)
    scenario_count = 99
    base_power = PSY.get_base_power(system)

    solar_data = _construct_fcst_data_ED(solar_fcst_quantiles, base_power, initial_time)
    wind_data = _construct_fcst_data_ED(wind_fcst_quantiles, base_power, initial_time)
    load_data = _construct_fcst_data_ED(load_fcst_quantiles, base_power, initial_time)

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