using Plots

include("../NYGrid/add_scenarios_ts.jl")
uc_ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO/Hour"
ed_ts_dir = "/Users/hanshu/Desktop/Price_formation/Data/generate_fr_KBoot/NYISO/Min5_3"

uc_solar_file = joinpath(uc_ts_dir, "solar_scenarios.h5")
uc_wind_file = joinpath(uc_ts_dir, "wind_scenarios.h5")
uc_load_file = joinpath(uc_ts_dir, "load_scenarios.h5")
initial_time = Dates.DateTime(2019, 1, 1)
base_power = 1.0
uc_solar_data = _construct_fcst_data_UC(uc_solar_file, base_power, initial_time)
uc_wind_data = _construct_fcst_data_UC(uc_wind_file, base_power, initial_time)
uc_load_data = _construct_fcst_data_UC(uc_load_file, base_power, initial_time)

ed_init_time = Dates.DateTime(2018, 12, 31, 20)
ed_solar_file = joinpath(ed_ts_dir, "solar_scenarios.h5")
ed_wind_file = joinpath(ed_ts_dir, "wind_scenarios.h5")
ed_load_file = joinpath(ed_ts_dir, "load_scenarios.h5")
ed_solar_data = _construct_fcst_data_ED(ed_solar_file, base_power, ed_init_time)
ed_wind_data = _construct_fcst_data_ED(ed_wind_file, base_power, ed_init_time)
ed_load_data = _construct_fcst_data_ED(ed_load_file, base_power, ed_init_time)


ed_x = 0:1/12:2-1/12
uc_x = 0:1:11
plot_time = initial_time + Dates.Hour(8)
plot(ed_x, ed_load_data[plot_time], label = "ED Load", xlabel = "Hour", ylabel = "MW", title = "Load Forecast")
plot!(uc_x, uc_load_data[plot_time][1:12], label = "UC Load")

ed_load_data[initial_time][1]
uc_load_data[initial_time][1]


initial_time = Dates.DateTime(2019, 1, 1)
ed_x = 0:1/12:2-1/12
p = plot(ed_x, ed_load_data[ed_init_time], xlabel = "Hour", ylabel = "MW", label = "", title = "Load Forecast")
for i in 1:12
    ed_x = i/12:1/12:i/12+2-1/12
    plot_time = ed_init_time + i*Minute(5)
    plot!(p, ed_x, ed_load_data[plot_time], label = "")
end

uc_x = 0:1:3
plot!(uc_x, uc_load_data[initial_time][1:4,:], linestyle = :dashdot, label = "UC Load")

display(p)

ed_load_data[initial_time]