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
base_power = 1.0
uc_solar_data = _construct_fcst_data_UC(uc_solar_file, base_power, initial_time)
uc_wind_data = _construct_fcst_data_UC(uc_wind_file, base_power, initial_time)
uc_load_data = _construct_fcst_data_UC(uc_load_file, base_power, initial_time)

ed_solar_file = joinpath(ed_ts_dir, "solar_scenarios.h5")
ed_wind_file = joinpath(ed_ts_dir, "wind_scenarios.h5")
ed_load_file = joinpath(ed_ts_dir, "load_scenarios.h5")
ed_solar_data = _construct_fcst_data_ED(ed_solar_file, base_power, initial_time)
ed_wind_data = _construct_fcst_data_ED(ed_wind_file, base_power, initial_time)
ed_load_data = _construct_fcst_data_ED(ed_load_file, base_power, initial_time)


ed_x = 0:1/12:2-1/12
uc_x = 0:1:11
plot_time = initial_time + Dates.Hour(8)
plot(ed_x, ed_load_data[plot_time], label = "ED Load", xlabel = "Hour", ylabel = "MW", title = "Load Forecast")
plot!(uc_x, uc_load_data[plot_time][1:12], label = "UC Load")

ed_load_data[initial_time][1]
uc_load_data[initial_time][1]


initial_time = Dates.DateTime(2019, 1, 1)
ed_x = 0:1/12:2-1/12
p = plot(ed_x, ed_load_data[initial_time], xlabel = "Hour", ylabel = "MW", label = "", title = "Load Forecast")
for i in 1:12
    ed_x = i/12:1/12:i/12+2-1/12
    plot_time = initial_time + i*Minute(5)
    plot!(p, ed_x, ed_load_data[plot_time], label = "")
end

uc_x = 0:1:3
plot!(uc_x, uc_load_data[initial_time][1:4,:], linestyle = :dashdot, label = "UC Load")

display(p)

ed_load_data[initial_time]