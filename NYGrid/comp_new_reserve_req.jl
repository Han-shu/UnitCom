include("../src/functions.jl")

using Dates, HDF5, Statistics

function _get_forecats_error(min5_flag::Bool, theta::Int)

    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/time_series"
    file_suffix = min5_flag ? "min5" : "hourly"
    solar_file = joinpath(ts_dir, "solar_scenarios_multi_" * file_suffix * ".h5")
    wind_file = joinpath(ts_dir, "wind_scenarios_multi_" * file_suffix * ".h5")
    load_file = joinpath(ts_dir, "load_scenarios_multi_" * file_suffix * ".h5")

    num_idx = h5open(load_file, "r") do file
        return length(read(file))
    end

    forecast_error = Dict()
    initial_time = Dates.DateTime(2018, 12, 31, 21)
    for ix in 1:num_idx
        if min5_flag
            curr_time = initial_time + Minute(5)*(ix - 1)
            if curr_time > Dates.DateTime(2019, 12, 31, 0)
                break
            end
        else
            curr_time = initial_time + Hour(ix - 1)
        end
        history_solar, solar_forecast = _extract_fcst_matrix(solar_file, curr_time, min5_flag)
        history_wind, wind_forecast = _extract_fcst_matrix(wind_file, curr_time, min5_flag)
        history_load, load_forecast = _extract_fcst_matrix(load_file, curr_time, min5_flag)
        base_netload = history_load - history_solar - history_wind
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

function comp_fixed_reserve_requirement(; min5_flag::Bool)
    theta = 11 #TODO
    forecast_error = _get_forecats_error(min5_flag, theta)
    reserve_requrement = Dict()
    for (time_idx, error) in forecast_error
        reserve_requrement[time_idx] = 1.5*std(error) #TODO
    end
    return reserve_requrement
end