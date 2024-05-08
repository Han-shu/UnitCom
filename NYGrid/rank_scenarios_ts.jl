# Add scenarios data by ranking the total net load 

using PowerSystems, Dates, HDF5, Statistics

# function _read_h5_by_idx(file, time)
#     idx_matrix = h5open(file, "r") do file
#         return read(file, string(time))
#     end
#     return idx_matrix
# end

function _read_h5_by_idx(file, time)
    return h5open(file, "r") do file
        return read(file, string(time))
    end
end

function _construct_rank_fcst_data(base_power::Float64, initial_time::DateTime; min5_flag::Bool=false)
    if min5_flag
        ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO_Min5"
    else
        ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO_Hour"
    end
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

        solar_data[curr_time] = solar_forecast./base_power
        wind_data[curr_time] = wind_forecast./base_power
        load_data[curr_time] = load_forecast./base_power
    end
    return solar_data, wind_data, load_data
end


function add_rank_scenarios_time_series!(system::System; min5_flag::Bool)::Nothing

    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    initial_time = Dates.DateTime(2018, 12, 31, 20)
    scenario_count = 10
    base_power = PSY.get_base_power(system)

    if min5_flag
        resolution = Dates.Minute(5)
    else
        resolution = Dates.Hour(1)
    end
    #construct data dict by ranking net load from low to high
    solar_data, wind_data, load_data =  _construct_rank_fcst_data(base_power, initial_time; min5_flag = min5_flag)

    scenario_forecast_data = Scenarios(
        name = "solar_power",
        resolution = resolution,
        data = solar_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, solar_gens, scenario_forecast_data)


    scenario_forecast_data = Scenarios(
        name = "wind_power",
        resolution = resolution,
        data = wind_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, wind_gens, scenario_forecast_data)

    scenario_forecast_data = Scenarios(
        name = "load",
        resolution = resolution,
        data = load_data,
        scenario_count = scenario_count,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, loads, scenario_forecast_data)

    _add_time_series_hydro!(system; min5_flag = min5_flag)
    
    return nothing
end