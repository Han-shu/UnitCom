include("NYGrid/build_ny_system.jl") # build the NYGrid system
include("NYGrid/add_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
include("src/functions.jl")


theta_value = 45 # set between 1 ~ 49 (Int)
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
initial_time = Dates.DateTime(2019, 1, 1)
horizon = 36
if !isnothing(theta_value)
    scenario_count = 1
    theta = theta_value
    model_name = "DLAUC_$(theta)"
else
    scenario_count = 10 # set scenario count 1 for deterministic, 10 for stochastic
    model_name = scenario_count == 1 ? "DLAUC" : "SLAUC"
end
today = Dates.today()
total_elapsed_time = 0.0

# add time series data
if !isnothing(theta_value)
    add_quantiles_time_series!(system)
else
    add_scenarios_time_series!(system)
end

solution_file = joinpath(result_dir, "$(model_name)_solution_$(today).json")
if !isfile(solution_file)
# 1. Run rolling horizon without solution from beginning
    @info "Running rolling horizon $(model_name) from beginning"  
    init_value, solution = init_rolling_uc(system; theta = theta_value)
else
# 2. Run rolling horizon with solution from previous time point
    @info "Find solution from $(solution_file)"
    init_value, solution = init_rolling_uc(system; solution_file = solution_file)
    initial_time = DateTime(String(solution["Time"][end]), "yyyy-mm-ddTHH:MM:SS")  + Dates.Hour(1)
    @info "Continue running rolling horizon $(model_name) starting from $(initial_time)"
end


for i in 1:500
    global total_elapsed_time, init_value, solution
    start_time = initial_time + Dates.Hour(i-1)
    if start_time >= DateTime(2019, 12, 30, 1)
        break
    end
    @info "Running rolling horizon $(model_name) for $(start_time)"
    elapsed_time = @elapsed begin
        model = stochastic_uc(system, Gurobi.Optimizer; init_value = init_value, theta = theta_value,
                    start_time = start_time, scenario_count = scenario_count, horizon = horizon)
        try
            init_value = _get_init_value(system, model)  
            solution = get_solution_uc_t(system, model, solution)
        catch e
            @warn "Error in solving $(model_name) for $(start_time): $e"
            break
        end
    end
    @info "Running UC for $(start_time) takes: $elapsed_time seconds"
    total_elapsed_time += elapsed_time
end
@info "Total elapsed time: $total_elapsed_time seconds"

# # save the solution
write_json(solution_file, solution)