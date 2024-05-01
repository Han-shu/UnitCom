using Plots

#---------------------------File Location---------------------------#
data_dir = "/Users/hanshu/Desktop/Price_formation/Data/ARPAE_NYISO"
solar_fcst_file = joinpath(data_dir, "BA_Existing_solar_intra-hour_fcst_2019.h5")
wind_fcst_file = joinpath(data_dir, "BA_Existing_wind_intra-hour_fcst_2019.h5")
load_fcst_file = joinpath(data_dir, "BA_load_intra-hour_fcst_2019.h5")
solar_actual_file = joinpath(data_dir, "BA_solar_actuals_Existing_2019.h5")
wind_actual_file = joinpath(data_dir, "BA_wind_actuals_Existing_2019.h5")
load_actual_file = joinpath(data_dir, "BA_load_actuals_min5_2019.h5")

#---------------------------Load Data---------------------------#
Actual = h5open(wind_actual_file, "r") do file
    return read(file)["actuals"]
end

max_wind_diff = 0
for i in eachindex(Actual)
    if i + 11 > length(Actual)
        break
    end
    max_wind_diff = max(max_wind_diff, abs(Actual[i] - Actual[i+11]))
end
println("Max wind difference in 1h: ", max_wind_diff)


plot(Actual[1:24], label = "Actuals", title = "Actuals", xlabel = "Time", ylabel = "MW")

include("../NYGrid/add_scenarios_ts.jl")
uc_ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO/Hour"
ed_ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO/Min5_2"

uc_solar_file = joinpath(uc_ts_dir, "solar_scenarios.h5")
uc_wind_file = joinpath(uc_ts_dir, "wind_scenarios.h5")
uc_load_file = joinpath(uc_ts_dir, "load_scenarios.h5")
initial_time = Dates.DateTime(2019, 1, 1)
base_power = 1
uc_solar_data = _construct_fcst_data_UC(solar_file, base_power, initial_time)
uc_wind_data = _construct_fcst_data_UC(wind_file, base_power, initial_time)
uc_load_data = _construct_fcst_data_UC(load_file, base_power, initial_time)

ed_solar_file = joinpath(ed_ts_dir, "solar_scenarios.h5")
ed_wind_file = joinpath(ed_ts_dir, "wind_scenarios.h5")
ed_load_file = joinpath(ed_ts_dir, "load_scenarios.h5")
ed_solar_data = _construct_fcst_data_ED(ed_solar_file, base_power, initial_time)
ed_wind_data = _construct_fcst_data_ED(ed_wind_file, base_power, initial_time)
ed_load_data = _construct_fcst_data_ED(ed_load_file, base_power, initial_time)


