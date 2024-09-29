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

function comp_new_reserve_requirement(min5_flag::Bool)
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
        mid_netload = load_forecast[:,6] - solar_forecast[:, 6] - wind_forecast[:, 6]
        time_idx = Hour(curr_time)
        if time_idx not in forecast_error
            forecast_error[time_idx] = [[base_netload - mid_netload]]
        else
            push!(forecast_error[time_idx], [base_netload - mid_netload])
        end
    end
    reserve_requirement = Dict()
    for (time_idx, error_list) in forecast_error
        reserve_requirement[time_idx] = mean(error_list)
    end
    return reserve_requirement
end


reserve_req = comp_new_reserve_requirement(false)