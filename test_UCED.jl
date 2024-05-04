include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")

# Open a file in append mode
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
log_file = open(joinpath(result_dir,"repl_log.txt"), "a")

# Redirect standard output and standard error
redirect_stdout(log_file)
redirect_stderr(log_file)

# Set parameters
theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36 # 36 hours
ed_horizon = 12 # 12*5 minutes = 1 hour
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
for t in 1:8760-uc_horizon+1
    global uc_model, ed_model, uc_sol, ed_sol, UC_init_value, ED_init_value
    uc_time = init_time + Hour(1)*(t-1)

    if t % 12 == 0
        write_json(uc_sol_file, uc_sol)
        write_json(ed_sol_file, ed_sol)
    end
    if t > 6 || uc_time > DateTime(2019,12,31,0)
        break
    end
    one_iter = @elapsed begin
    @info "Solving UC model at $(uc_time)"
    one_uc_time = @elapsed begin
    UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model, uc_sol = uc_sol, ed_sol = ed_sol)  
    uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                        start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)
    end
    @info "UC model at $(uc_time) is solved in $(one_uc_time) seconds"
    # Get commitment status that will be passed to ED
    uc_status = _get_binary_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
    one_hour_ed_time = @elapsed begin
    ed_hour_sol = init_solution_ed(EDsys)
    for i in 1:12
        @info "Running length $(length(ed_hour_sol["LMP"]))"
        ed_time = uc_time + Minute(5*(i-1))
        @info "Solving ED model at $(ed_time)"
        ED_init_value = _get_init_value_for_ED(EDsys, uc_status; UC_init_value = UC_init_value, ed_model = ed_model)
        ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)
        ed_hour_sol = get_solution_ed(EDsys, ed_model, ed_hour_sol)
        if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
            @warn "ED model at $(ed_time) is with status $(primal_status(ed_model))"
            break
        end
    end

    if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        break
    end
    end
    @info "ED model at $(uc_time) is solved in $(one_hour_ed_time) seconds"
    uc_sol = get_solution_uc(UCsys, uc_model, ed_hour_sol, uc_sol)
    @info "UC solution is updated"
    ed_sol = merge_ed_solution(ed_sol, ed_hour_sol)
    @info "ED solution is merged"
end
    @info "One iteration takes $(one_iter) seconds"
end

# uc_time = init_time + Hour(1)*(1-1)
# UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model, uc_sol = uc_sol, ed_sol = ed_sol)  
# uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
#                 start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)

# # Restore standard output and error
redirect_stdout()
redirect_stderr()

# Close the log file
close(log_file)
