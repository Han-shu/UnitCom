include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")

# Set parameters
theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36 # 36 hours
ed_horizon = 12 # 12*5 minutes = 1 hour
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
model_name, uc_sol_file, ed_sol_file = get_UCED_model_file_name(theta = theta, scenario_count = scenario_count, result_dir = result_dir)

# Build NY system for UC and ED
@info "Build NY system for UC"
UCsys = build_ny_system(base_power = 100)
@info "Build NY system for ED"
EDsys = build_ny_system(base_power = 100)

if !isnothing(theta)
    @info "Adding quantile time series data for UC"
    add_quantiles_time_series_UC!(UCsys)
    @info "Adding quantile time series data for ED"
    add_quantiles_time_series_ED!(EDsys)
else
    @info "Adding scenarios time series data for UC"
    add_scenarios_time_series_UC!(UCsys)
    @info "Adding scenarios time series data for ED"
    add_scenarios_time_series_ED!(EDsys)
end