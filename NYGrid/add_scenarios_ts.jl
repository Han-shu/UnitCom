# Add scenarios data by ranking the total net load 

using PowerSystems, Dates, HDF5, Statistics

function _read_h5_by_idx(file, time)
    return h5open(file, "r") do file
        return read(file, string(time))
    end
end

function _construct_fcst_data(base_power::Float64, initial_time::DateTime; min5_flag::Bool, rank_netload::Bool)
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


function add_scenarios_time_series!(system::System; min5_flag::Bool, rank_netload::Bool = false)::Nothing

    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    initial_time = Dates.DateTime(2018, 12, 31, 20)
    scenario_cnt = 11
    base_power = PSY.get_base_power(system)
    resolution = min5_flag ? Dates.Minute(5) : Dates.Hour(1)

    #construct data dict (rank_netload = true: ranking senarios by net load from low to high)
    solar_data, wind_data, load_data = _construct_fcst_data(base_power, initial_time; min5_flag = min5_flag, rank_netload = rank_netload)

    scenario_forecast_data = Scenarios(
        name = "solar_power",
        resolution = resolution,
        data = solar_data,
        scenario_cnt = scenario_cnt,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, solar_gens, scenario_forecast_data)


    scenario_forecast_data = Scenarios(
        name = "wind_power",
        resolution = resolution,
        data = wind_data,
        scenario_cnt = scenario_cnt,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, wind_gens, scenario_forecast_data)

    scenario_forecast_data = Scenarios(
        name = "load",
        resolution = resolution,
        data = load_data,
        scenario_cnt = scenario_cnt,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, loads, scenario_forecast_data)

    _add_time_series_hydro!(system; min5_flag = min5_flag)
    
    return nothing
end


function _add_time_series_hydro!(system::System; min5_flag)::Nothing
    hydro_file = "/Users/hanshu/Desktop/Price_formation/Data/NYGrid/hydro_2019.csv"
    df_ts = CSV.read(hydro_file, DataFrame)
    init_time = Dates.DateTime(2018, 12, 31, 20)
    df_ts = df_ts[df_ts.Time_Stamp .>= init_time, :]
    # Get hourly average
    if min5_flag
        data = TimeArray(df_ts.Time_Stamp, df_ts.Gen_MW)
    else
        min5_ts = df_ts.Gen_MW
        hour_ts = [sum(min5_ts[i:i+11])/12 for i in 1:12:size(min5_ts, 1)]
        dates = range(init_time, step=Dates.Hour(1), length=size(hour_ts, 1))
        data = TimeArray(dates, hour_ts)
    end
    hy_ts = SingleTimeSeries("hydro_power", data)
    hydro_gen = first(get_components(HydroDispatch, system))
    add_time_series!(system, hydro_gen, hy_ts)

    return nothing
end