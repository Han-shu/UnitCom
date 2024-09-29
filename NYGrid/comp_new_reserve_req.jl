
function _read_h5_by_idx(file, time)
    return h5open(file, "r") do file
        return read(file, string(time))
    end
end

function comp_new_reserve_requirement(min5_flag::Bool, rank_netload::Bool)
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

    forecast_error = Dict{Dates.DateTime, Matrix{Float64}}()
    for ix in 1:num_idx
        if min5_flag
            curr_time = initial_time + Minute(5)*(ix - 1)
        else
            curr_time = initial_time + Hour(ix - 1)
        end
        solar_forecast = _read_h5_by_idx(solar_file, curr_time)
        wind_forecast = _read_h5_by_idx(wind_file, curr_time)
        load_forecast = _read_h5_by_idx(load_file, curr_time)
        net_load = load_forecast - solar_forecast - wind_forecast
        net_load_path = sum(net_load, dims=1)
        net_load_rank = sortperm(vec(net_load_path)) # from low to high
        solar_forecast = solar_forecast[:, net_load_rank] # sort by rank
        wind_forecast = wind_forecast[:, net_load_rank]
        load_forecast = load_forecast[:, net_load_rank] 
        forecast_error[curr_time] = load_forecast - solar_forecast - wind_forecast
    end
    return reserve_requirement
end


function reference()
    solar_data = Dict{Dates.DateTime, Matrix{Float64}}()
    wind_data = Dict{Dates.DateTime, Matrix{Float64}}()
    load_data = Dict{Dates.DateTime, Matrix{Float64}}()

    for ix in 1:num_idx
        if min5_flag
            curr_time = initial_time + Minute(5)*(ix - 1)
        else
            curr_time = initial_time + Hour(ix - 1)
        end
        solar_forecast = _read_h5_by_idx(solar_file, curr_time)
        wind_forecast = _read_h5_by_idx(wind_file, curr_time)
        load_forecast = _read_h5_by_idx(load_file, curr_time)

        if rank_netload
            net_load = load_forecast - solar_forecast - wind_forecast
            net_load_path = sum(net_load, dims=1)
            net_load_rank = sortperm(vec(net_load_path)) # from low to high
            solar_forecast = solar_forecast[:, net_load_rank] # sort by rank
            wind_forecast = wind_forecast[:, net_load_rank]
            load_forecast = load_forecast[:, net_load_rank] 
        end

        solar_data[curr_time] = solar_forecast./base_power
        wind_data[curr_time] = wind_forecast./base_power
        load_data[curr_time] = load_forecast./base_power
    end
    return solar_data, wind_data, load_data
end