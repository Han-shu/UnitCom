using Plots

include("../NYGrid/add_scenarios_ts.jl")

initial_time = Dates.DateTime(2018, 12, 31, 21)
base_power = 1.0
uc_solar_data, uc_wind_data, uc_load_data = _construct_fcst_data(base_power, initial_time; min5_flag = false, rank_netload = true)
ed_solar_data, ed_wind_data, ed_load_data = _construct_fcst_data(base_power, initial_time; min5_flag = true, rank_netload = true)


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

