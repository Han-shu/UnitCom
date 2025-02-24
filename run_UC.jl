include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/comp_new_reserve_req.jl")
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")
include("src/get_uc_dual.jl")

# Run rolling horizon UC model only 
#=
    POLICY
    "PF": Perfect forecast
    "SB": Stochastic benchmark, contingency reserve only, no new reserve requirement
    "MF": mean forecast
    "BF": Biased forecast ((1-p)*mean + p*WF, p = 0.5 by default) 
        Use different p by specifying $"BF(X)" where X::Int = 5, 6, 7, 8, 9
        Example:
            "BF8": Biased forecast with p = 0.8
            "BF9": Biased forecast with p = 0.9
    "WF": Worst forecast (highest net load case)
    "DR60": Dynamic reserve requirement to be added to 60T
    "DR30": Dynamic reserve requirement to be added to 30T
=#

# Specify the policy and running date
POLICY = "DR30" # "SB", "PF", "MF", "BF", "WF", "DR60", "DR30" 
run_date = Date(2025,2,22)
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
uc_horizon = 36 # hours

# Save the solution when day is in save_date: save SB more frequently to release memory
save_date = POLICY == "SB" ? [1, 11, 21] : [1] 
scenario_cnt = POLICY == "SB" ? 11 : 1 # only SB is with 11 scenarios (stochastic), o.w. 1 scenario (deterministic)
master_folder, uc_folder, ed_folder = policy_model_folder_name(POLICY, run_date)

@info "Policy: $(POLICY), Master folder: $(master_folder), UC folder: $(uc_folder)"
@info "UC horizon: $(uc_horizon)"

# Build NY system and Add time series data
@info "Build NY system for UC"
UCsys = build_ny_system(base_power = 100)
@info "Adding scenarios time series data for UC"
add_scenarios_time_series!(POLICY, UCsys; min5_flag = false)

# Create Master Model folder if not exist
if !ispath(joinpath(result_dir, master_folder))
    @info "Create Master folder for $(POLICY) at $(joinpath(result_dir, master_folder))"
    mkdir(joinpath(result_dir, master_folder))
end

@info "Running rolling horizon $(POLICY) from beginning"  
# Create folders if not exist
if !ispath(joinpath(result_dir, master_folder, POLICY))
    mkdir(joinpath(result_dir, master_folder, POLICY))
    @info "Create folders $(joinpath(result_dir, master_folder, POLICY, uc_folder)) and $(joinpath(result_dir, master_folder, POLICY, ed_folder))"
    mkdir(joinpath(result_dir, master_folder, POLICY, uc_folder))
    mkdir(joinpath(result_dir, master_folder, POLICY, ed_folder))
end

init_time = DateTime(2019, 7, 30, 0)
uc_sol = init_solution_uc_only(UCsys)
UC_init_value = _get_init_value_for_UC(UCsys; horizon = 12, scenario_cnt = scenario_cnt, init_fr_ED_flag = true, start_time = init_time)

# Run rolling horizon UC-ED
for t in 1:8760
    global POLICY, uc_time, uc_sol_file
    global uc_model, uc_sol, UC_init_value
    
    uc_time = init_time + Hour(1)*(t-1)
    # Break condition
    if uc_time > DateTime(2019,9,1,1) 
        break
    end

    # For the first hour of the month, save the solution and reinitialize
    if day(uc_time) in save_date && hour(uc_time) == 0
        # save the solution only if final hour of last month has been solved
        if length(uc_sol["Time"]) > 0 && uc_sol["Time"][end] == uc_time - Hour(1)
            uc_sol_file = joinpath(result_dir, master_folder, POLICY, uc_folder, "UC_$(Date(uc_time - Hour(1))).json")
            @info "Saving the solutions to $(uc_sol_file)"
            write_json(uc_sol_file, uc_sol)
        end

        @info "Reinitialize the solution"
        uc_sol = init_solution_uc_only(UCsys)
    end

    @info "Solving UC model at $(uc_time)"
    one_uc_time = @elapsed begin
        # Solve UC model (MIP)
        uc_model = stochastic_uc(UCsys, Gurobi.Optimizer, VOLL; init_value = UC_init_value,
                            start_time = uc_time, scenario_count = scenario_cnt, horizon = uc_horizon)
        # update UC_init_value for the next UC model                   
        UC_init_value = _get_init_value_for_UC(UCsys; scenario_cnt = scenario_cnt, uc_model = uc_model) 
    
        uc_sol = get_solution_uc(UCsys, uc_model, uc_sol)
        # update the history_LMP from uc_sol
        push!(UC_init_value.history_LMP, uc_sol["LMP fix"][end][1])
        if length(UC_init_value.history_LMP) > 368
            popfirst!(UC_init_value.history_LMP)
        end
    end
    @info "$(POLICY)-UC model at $(uc_time) is solved in $(one_uc_time) seconds"
end

@info "Running rolling horizon $(POLICY) is completed at $(uc_time)"
@info "Current time is $(now())"