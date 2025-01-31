include("../src/functions.jl")


using PowerSystems, Dates, HDF5, Statistics


"""
    _construct_fcst_data(base_power::Float64; min5_flag::Bool, rank_netload::Bool)
    return solar_data, wind_data, load_data for forecast data in h5 files
    x_data: Dict{Dates.DateTime, Matrix{Float64}} where x = solar, wind, load
    key = time, value = forecast data indexed by time
"""
function _construct_fcst_data(POLICY::String, base_power::Float64; min5_flag::Bool)
    ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/time_series"
    file_suffix = min5_flag ? "min5" : "hourly"
    solar_file = joinpath(ts_dir, "solar_scenarios_multi_" * file_suffix * ".h5")
    wind_file = joinpath(ts_dir, "wind_scenarios_multi_" * file_suffix * ".h5")
    load_file = joinpath(ts_dir, "load_scenarios_multi_" * file_suffix * ".h5")

    num_idx = h5open(load_file, "r") do file
        return length(read(file))
    end

    solar_data = Dict{Dates.DateTime, Matrix{Float64}}()
    wind_data = Dict{Dates.DateTime, Matrix{Float64}}()
    load_data = Dict{Dates.DateTime, Matrix{Float64}}()

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

        if POLICY == "WF" # rank by net load at each time step
            net_load = load_forecast .- solar_forecast .- wind_forecast
            for i in 1:size(net_load, 1)
                rank = sortperm(net_load[i, :])
                solar_forecast[i, :] = solar_forecast[i, rank]
                wind_forecast[i, :] = wind_forecast[i, rank]
                load_forecast[i, :] = load_forecast[i, rank]
            end
        end

        if POLICY == "PF" # replace the first scenario with the historical data
            solar_forecast = hcat(reshape(history_solar, :, 1) , solar_forecast[:, 2:end])
            wind_forecast = hcat(reshape(history_wind, :, 1), wind_forecast[:, 2:end])
            load_forecast = hcat(reshape(history_load, :, 1), load_forecast[:, 2:end])
        end

        solar_data[curr_time] = solar_forecast./base_power
        wind_data[curr_time] = wind_forecast./base_power
        load_data[curr_time] = load_forecast./base_power
    end
    return solar_data, wind_data, load_data
end


function add_scenarios_time_series!(POLICY::String, system::System; min5_flag::Bool)::Nothing

    loads = collect(get_components(StaticLoad, system))
    wind_gens = get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system)
    solar_gens = get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system)

    scenario_cnt = 11 
    base_power = PSY.get_base_power(system)
    resolution = min5_flag ? Dates.Minute(5) : Dates.Hour(1)

    #construct data dict according to the policy
    solar_data, wind_data, load_data = _construct_fcst_data(POLICY, base_power; min5_flag = min5_flag)

    scenario_forecast_data = Scenarios(
        name = "solar_power",
        resolution = resolution,
        data = solar_data,
        scenario_count = scenario_cnt,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, solar_gens, scenario_forecast_data)


    scenario_forecast_data = Scenarios(
        name = "wind_power",
        resolution = resolution,
        data = wind_data,
        scenario_count = scenario_cnt,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, wind_gens, scenario_forecast_data)

    scenario_forecast_data = Scenarios(
        name = "load",
        resolution = resolution,
        data = load_data,
        scenario_count = scenario_cnt,
        scaling_factor_multiplier = PSY.get_base_power
    )
    add_time_series!(system, loads, scenario_forecast_data)

    _add_time_series_hydro!(system; min5_flag = min5_flag)
    
    return nothing
end


function _add_time_series_hydro!(system::System; min5_flag)::Nothing
    hydro_file = "/Users/hanshu/Desktop/Price_formation/Data/NYGrid/hydro_2019.csv"
    df_ts = CSV.read(hydro_file, DataFrame)
    init_time = Dates.DateTime(2018, 12, 31, 21)
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

#TODO: add_fixed_reserve_time_series! function
# function add_fixed_reserve_time_series!(system::System, theta::Int64; min5_flag::Bool)::Nothing
#     reserve_requirment_ts = comp_fixed_reserve_requirement(min5_flag, theta)
#     reserve = first(get_componets(VariableReserve, system))
#     PSY.set_ext!(reserve, reserve_requirment_ts)
#     return nothing
# end
    
