using KBoot
using HDF5
using CSV, DataFrames, Plots, StatsPlots, Distributions, Random, KernelDensity, Dates, NearestNeighbors, Statistics, TimeZones, HDF5

function covert2array(vec_df::Vector{Any})::Array{Float64, 2}
    array = zeros(Float64, length(vec_df[1].BA_total), length(vec_df))
    for (i, df) in enumerate(vec_df)
        array[:, i] = df.BA_total
    end
    return array
end

# load historical quantiles
df_wind = CSV.read("Historical Quantiles/df_wind_2018_historical_quantiles.csv", DataFrame);
df_solar = CSV.read("Historical Quantiles/df_solar_2018_historical_quantiles.csv", DataFrame);
df_load = CSV.read("Historical Quantiles/df_load_2018_historical_quantiles.csv", DataFrame);

# correction DateTimeTexas
df_wind.DateTimeTexas = df_wind.DateTime .- Hour(6);
df_solar.DateTimeTexas = df_solar.DateTime .- Hour(6);
df_load.DateTimeTexas = df_load.DateTime .- Hour(6);

# correcting extracted_hour
df_wind.extracted_hour = hour.(df_wind.DateTimeTexas);
df_solar.extracted_hour = hour.(df_solar.DateTimeTexas);
df_load.extracted_hour = hour.(df_load.DateTimeTexas);

# load quantile data
wind_event_quantile = CSV.read("Quantiles/Wind Quantiles.csv", DataFrame);
solar_event_quantile = CSV.read("Quantiles/Solar Quantiles.csv", DataFrame);
load_event_quantile = CSV.read("Quantiles/Load Quantiles.csv", DataFrame);

hour_of_interest = 0;
horizon = 48;
k = 10; # setting the number of nearest neighbors
initial_time = Dates.Date(2018, 1, 1)

output_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/"

for i in 1:365
    run_date = initial_time + Day(i - 1)
    month_of_interest = Dates.month(run_date)
    day_of_interest = Dates.day(run_date)
    wind_plot1, solar_plot1, load_plot1, q_knn1, v_knn1, wind_scenario_blocks_final_variance1, solar_scenario_blocks_final_variance1, load_scenario_blocks_final_variance1 = KBoot.scenario_generation(df_wind, df_solar, df_load, wind_event_quantile, solar_event_quantile, load_event_quantile, month_of_interest, day_of_interest, horizon, hour_of_interest, k);
    load_scenarios_array = covert2array(load_scenario_blocks_final_variance1)
    h5open(output_dir*"load_scenarios.h5", "cw") do file
        write(file, string(run_date), load_scenarios_array)
    end
    solar_scenarios_array = covert2array(solar_scenario_blocks_final_variance1)
    h5open(output_dir*"solar_scenarios.h5", "cw") do file
        write(file, string(run_date), solar_scenarios_array)
    end
    wind_scenarios_array = covert2array(wind_scenario_blocks_final_variance1)
    h5open(output_dir*"wind_scenarios.h5", "cw") do file
        write(file, string(run_date), wind_scenarios_array)
    end
end

