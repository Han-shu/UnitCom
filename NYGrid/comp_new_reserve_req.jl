using Dates, HDF5, Statistics

function _read_h5_by_idx(file::String, time::Dates.DateTime)
    return h5open(file, "r") do file
        return read(file, string(time))
    end
end

function _extract_fcst_matrix(file::String, time::Dates.DateTime, min5_flag::Bool)
    matrix = _read_h5_by_idx(file, time)
    if min5_flag
        return matrix[:, 1], matrix[:, 2:end]
    else
        return matrix[2:end, 1], matrix[2:end, 2:end]
    end
end

function _get_forecats_error(min5_flag::Bool, theta::Int64)
    if min5_flag
        ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO_Min5"
    else
        ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO_Hour"
    end
    solar_file = joinpath(ts_dir, "solar_scenarios.h5")
    wind_file = joinpath(ts_dir, "wind_scenarios.h5")
    load_file = joinpath(ts_dir, "load_scenarios.h5")

    num_idx = h5open(load_file, "r") do file
        return length(read(file))
    end

    forecast_error = Dict()
    initial_time = Dates.DateTime(2018, 12, 31, 20)
    for ix in 1:num_idx
        if min5_flag
            curr_time = initial_time + Minute(5)*(ix - 1)
        else
            curr_time = initial_time + Hour(ix - 1)
        end
        base_solar, solar_forecast = _extract_fcst_matrix(solar_file, curr_time, min5_flag)
        base_wind, wind_forecast = _extract_fcst_matrix(wind_file, curr_time, min5_flag)
        base_load, load_forecast = _extract_fcst_matrix(load_file, curr_time, min5_flag)
        base_netload = base_load - base_solar - base_wind
        net_load = load_forecast - solar_forecast - wind_forecast
        net_load_path = sum(net_load, dims=1)
        net_load_rank = sortperm(vec(net_load_path)) # from low to high
        solar_forecast = solar_forecast[:, net_load_rank] # sort by rank
        wind_forecast = wind_forecast[:, net_load_rank]
        load_forecast = load_forecast[:, net_load_rank] 
        mid_netload = load_forecast[:,theta] - solar_forecast[:, theta] - wind_forecast[:, theta]
        time_idx = (Dates.hour(curr_time), Dates.minute(curr_time))
        error = base_netload - mid_netload
        append!(get!(forecast_error, time_idx, []), [error])
    end
    return forecast_error
end

function comp_fixed_reserve_requirement(theta::Int64; min5_flag::Bool)
    forecast_error = _get_forecats_error(min5_flag, theta)
    reserve_requrement = Dict()
    for (time_idx, error) in forecast_error
        reserve_requrement[time_idx] = 1.5*std(error) #TODO
    end
    return reserve_requrement
end