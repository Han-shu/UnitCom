include("NYGrid/build_ny_system.jl") # build the NYGrid system
include("NYGrid/add_ts.jl") # add time series data
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
include("src/functions.jl")

initial_time = Dates.DateTime(2019, 1, 1)
horizon = 36
total_elapsed_time = 0.0

# Run rolling horizon with solution from previous time point
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
solution_file = joinpath(result_dir, "solution2.json")
init_value, solution = init_rolling_uc(system; solution_file = solution_file)

# Run rolling horizon without solution from previous time point
# init_value, solution = init_rolling_uc(system)

if length(solution["Time"]) > 0
    initial_time = DateTime(String(solution["Time"][end]), "yyyy-mm-ddTHH:MM:SS")  + Dates.Hour(1)
end

for i in 1:30#8712
    global total_elapsed_time, init_value, solution
    start_time = initial_time + Dates.Hour(i-1)
    @info "Running rolling horizon UC for $(start_time)"
    elapsed_time = @elapsed begin
        model = stochastic_uc(system, Gurobi.Optimizer, init_value = init_value, 
                    start_time = start_time, scenario_count = 10, horizon = horizon)
        init_value = _get_init_value(system, model)  
        solution = get_solution_uc_t(system, model, solution)
    end
    @info "Running UC for $(start_time) takes: $elapsed_time seconds"
    total_elapsed_time += elapsed_time
end
@info "Total elapsed time: $total_elapsed_time seconds"

# save the solution
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
write_json(joinpath(result_dir, "solution2.json"), solution)


