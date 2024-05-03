include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")

# Open a file in append mode
log_file = open("repl_log.txt", "a")

# Redirect standard output and standard error
redirect_stdout(log_file)
redirect_stderr(log_file)

# Set parameters
theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36 # 36 hours
ed_horizon = 12 # 12*5 minutes = 1 hour
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
model_name = "UCED"
uc_sol_file = joinpath(result_dir, "$(model_name)_sol_$(Dates.today()).json")
ed_sol_file = joinpath(result_dir, "ED_sol_$(Dates.today()).json")

# Build NY system for UC and ED
@info "Build NY system for UC"
UCsys = build_ny_system(base_power = 100)
# Add time series data
if !isnothing(theta)
    @info "Adding quantile time series data for UC"
    add_quantiles_time_series!(UCsys)
else
    @info "Adding scenarios time series data for UC"
    add_scenarios_time_series_UC!(UCsys)
end

@info "Build NY system for ED"
EDsys = build_ny_system(base_power = 100)
@info "Adding scenarios time series data for ED"
add_scenarios_time_series_ED!(EDsys)

# Initialize the solution
if !isfile(uc_sol_file)
# 1. Run rolling horizon without solution from beginning
    @info "Running rolling horizon $(model_name) from beginning"  
    init_time = DateTime(2019,1,1)
    uc_model, ed_model = nothing, nothing
    uc_sol = init_solution_uc(UCsys)
    ed_sol = init_solution_ed(EDsys)
else
# 2. Run rolling horizon with solution from previous time point
    @info "Find solution from $(uc_sol_file)"
    uc_sol = read_json(uc_sol_file)
    ed_sol = read_json(ed_sol_file)
    init_time = DateTime(String(uc_sol["Time"][end]), "yyyy-mm-ddTHH:MM:SS")  + Dates.Hour(1)
    @info "Continue running rolling horizon $(model_name) starting from $(init_time)"
    uc_model, ed_model = JuMP.Model(), nothing
end

# Run rolling horizon UC-ED
uc_time = init_time + Hour(1)*(1-1)
UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model, uc_sol = uc_sol, ed_sol = ed_sol)  
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)

# # Restore standard output and error
redirect_stdout()
redirect_stderr()

# Close the log file
close(log_file)
