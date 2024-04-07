# Load the NYGrid data
include("NYGrid/build_ny_system.jl") # build the system
include("NYGrid/add_ts.jl") # add time series data
include("src/stochastic_uc.jl")
include("src/get_solution.jl")
include("src/write_json.jl")

initial_time = Dates.DateTime(2019, 1, 1)
horizon = 24
total_elapsed_time = 0.0
init_value = _get_init_value(system)
solution = initiate_solution_uc_t(system)
for i in 1:8712
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
write_json(joinpath(result_dir, "solution.json"), solution)


