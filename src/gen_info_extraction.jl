using PowerSystems, Gurobi, JuMP
using PowerSystemCaseBuilder
using Dates
using TimeSeries

sys = System("/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/DA_sys_31_scenarios.json")

get_components(ThermalMultiStart, sys)
get_components(RenewableDispatch, sys)
thermal_gen_names = get_name.(get_components(ThermalGen, sys))
renewable_gen_names = get_name.(get_components(RenewableGen, sys))

thermal_gen_names2 = get_name.(get_components(ThermalMultiStart, sys))
renewable_gen_names2 = get_name.(get_components(RenewableDispatch, sys))


file_dir = joinpath(pkgdir(PowerSystems), "docs", "src", "tutorials", "tutorials_data")
system = System(joinpath(file_dir, "RTS_GMLC.m"));
to_json(system, "system.json")
system2 = System("system.json")


resolution = Dates.Hour(1)
data = Dict(
    DateTime("2020-01-01T00:00:00") => 10.0*ones(24),
    DateTime("2020-01-01T01:00:00") => 5.0*ones(24),
)
forecast = Deterministic("max_active_power", data, resolution)


resolution = Dates.Hour(1)
dates = range(DateTime("2020-01-01T00:00:00"), step = resolution, length = 24)
data = TimeArray(dates, ones(24))
time_series = SingleTimeSeries("max_active_power", data)


# Create static time series data.
resolution = Dates.Hour(1)
dates = range(DateTime("2020-01-01T00:00:00"), step = resolution, length = 8760)
data = TimeArray(dates, ones(8760))
ts = SingleTimeSeries("max_active_power", data)
add_time_series!(sys, component, ts)

# Transform it to Deterministic
transform_single_time_series!(sys, 24, Hour(24))
