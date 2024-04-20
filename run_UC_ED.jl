include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
include("src/functions.jl")

# DLAC-NLB: theta 1~49, scenario_count = 1
# DLAC-AVG: theta = nothing, scenario_count = 1
# SLAC: theta = nothing, scenario_count = 10

theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36
ed_horizon = 24
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
initial_time = Dates.DateTime(2019, 1, 1)
model_name, solution_file = get_model_file_name(theta = theta, scenario_count = scenario_count, result_dir = result_dir)

@info "Build NY system"
UCsys = build_ny_system(base_power = 100)
# add time series data
if !isnothing(theta)
    @info "Adding quantile time series data for UC"
    add_quantiles_time_series!(UCsys)
else
    @info "Adding scenarios time series data for UC"
    add_scenarios_time_series!(UCsys)
end

EDsys = build_ny_system(base_power = 100)
@info "Adding scenarios time series data for ED"
add_scenarios_time_series_ED!(EDsys)

start_time = DateTime(2019,1,1)
UC_init_value, solution = init_rolling_uc(UCsys; theta = theta)
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                    start_time = start_time, scenario_count = scenario_count, horizon = uc_horizon)
UC_init_value = _get_init_value(system, model)  
solution = get_solution_uc_t(system, model, solution)
ED_init_value = _get_init_value(system, model)
ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = start_time, horizon = ed_horizon)


# # save the solution
# write_json(solution_file, solution)