include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")
# DLAC-NLB: theta 1~49, scenario_count = 1
# DLAC-AVG: theta = nothing, scenario_count = 1
# SLAC: theta = nothing, scenario_count = 10

theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36
ed_horizon = 12
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
    add_scenarios_time_series_UC!(UCsys)
end

EDsys = build_ny_system(base_power = 100)
@info "Adding scenarios time series data for ED"
add_scenarios_time_series_ED!(EDsys)

start_time = DateTime(2019,1,1)


# UC_init_value, solution = init_rolling_uc(UCsys; theta = theta)
# ED_init_value = _get_init_value_for_ED(EDsys; CoverHour = 2)
global uc_model, ed_model
uc_model, ed_model = nothing, nothing
# for i in 1:8760-uc_horizon+1

i = 1
uc_time = start_time + Hour(1)*(i-1)
@info "Solving UC model at $(uc_time)"
UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                    start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)

ug_t0 = _get_commitment_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
for t in 1:12
    ed_time = uc_time + Minute(5*(t-1))
    @info "Solving ED model at $(ed_time)"
    ED_init_value = _get_init_value_for_ED(EDsys, ug_t0; ed_model = ed_model)
    ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)
end

# solution = get_solution_uc_t(system, model, solution)



# # save the solution
# write_json(solution_file, solution)