include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("NYGrid/comp_new_reserve_req.jl")
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")
include("src/get_uc_op_price.jl")

#=
    POLICY
    "PF": Perfect forecast
    "SB": Stochastic benchmark, contingency reserve only, no new reserve requirement
    "MF": mean forecast
    "BF": Biased forecast ((1-p)*mean + p*WF, p = 0.5)
    "WF": Worst forecast (highest net load case, theta = 11)
    ~~"FR": Fixed reserve requirement~~
    "DR": Dynamic reserve requirement
    "DR30": Dynamic reserve requirement to be added to 30T
=#

# Specify the policy and running date
POLICY = "MF" #, "BF", "WF", "DR"
run_date = Date(2024,11,2)
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"

master_folder, uc_folder, ed_folder = policy_model_folder_name(POLICY, run_date)
theta, scenario_cnt = policy_theta_parameter(POLICY)
uc_horizon = 36 # 36 hours
ed_horizon = 12 # 12*5 minutes = 1 hour
@info "Policy: $(POLICY), Master folder: $(master_folder), UC folder: $(uc_folder), ED folder: $(ed_folder)"
@info "UC horizon: $(uc_horizon), ED horizon: $(ed_horizon)"


# Build NY system for UC and ED
@info "Build NY system for UC"
UCsys = build_ny_system(base_power = 100)
@info "Build NY system for ED"
EDsys = build_ny_system(base_power = 100)


# Add time series data
@info "Adding scenarios time series data for UC"
add_scenarios_time_series!(POLICY, UCsys; min5_flag = false)
@info "Adding scenarios time series data for ED"
add_scenarios_time_series!(POLICY, EDsys; min5_flag = true)

# Compute fixed reserve requirement for FR policy
reserve_requirement = Dict()
if POLICY == "FR"
    reserve_requirement["UC"] = comp_fixed_reserve_requirement(theta; min5_flag = false)
    reserve_requirement["ED"] = comp_fixed_reserve_requirement(theta; min5_flag = true)
end

# Create Master Model folder if not exist
if !ispath(joinpath(result_dir, master_folder))
    @info "Create Master folder for $(POLICY) at $(joinpath(result_dir, master_folder))"
    mkdir(joinpath(result_dir, master_folder))
end

# Determine the initial flag: run from beginning or continue from previous solution
init_fr_ED_flag, init_fr_file_flag = determine_init_flag(result_dir, master_folder, POLICY, uc_folder, ed_folder)

if init_fr_ED_flag
# 1. Run rolling horizon without solution from beginning
    @info "Running rolling horizon $(POLICY) from beginning"  
    # Create folders if not exist
    if !ispath(joinpath(result_dir, master_folder, POLICY))
        mkdir(joinpath(result_dir, master_folder, POLICY))
        @info "Create folders $(joinpath(result_dir, master_folder, POLICY, uc_folder)) and $(joinpath(result_dir, master_folder, POLICY, ed_folder))"
        mkdir(joinpath(result_dir, master_folder, POLICY, uc_folder))
        mkdir(joinpath(result_dir, master_folder, POLICY, ed_folder))
    end
    init_time = DateTime(2018, 12, 31, 21)
    uc_sol = init_solution_uc(UCsys)
    ed_sol = init_ed_solution(EDsys)
    UC_init_value = _get_init_value_for_UC(UCsys; init_fr_ED_flag = true)
else
# 2. Run rolling horizon with solution from previous time point
    @info "Find path $(joinpath(result_dir, master_folder, POLICY, uc_folder))"
    # Find the latest solution file
    uc_sol_file, ed_sol_file = find_sol_files(result_dir, master_folder, POLICY, uc_folder, ed_folder)
    @info "Find the latest solution file $(uc_sol_file) and $(ed_sol_file)"
    uc_sol = read_json(uc_sol_file)
    ed_sol = read_json(ed_sol_file)
    init_time = DateTime(String(uc_sol["Time"][end]), "yyyy-mm-ddTHH:MM:SS")  + Dates.Hour(1)
    @info "Continue running rolling horizon $(POLICY) starting from $(init_time)"
    UC_init_value = _get_init_value_for_UC(UCsys; uc_sol = uc_sol, ed_sol = ed_sol, init_fr_file_flag = true)
end
ed_model = nothing


# Run rolling horizon UC-ED
for t in 1:8760
    global POLICY, reserve_requirement
    global uc_model, ed_model, uc_sol, ed_sol, UC_init_value, ED_init_value
    global uc_time, init_fr_file_flag, init_fr_ED_flag, uc_sol_file, ed_sol_file
    uc_time = init_time + Hour(1)*(t-1)
    
    # Break condition
    if t > 1500 || uc_time > DateTime(2019,3,1,2) 
        break
    end
    
    # For the first hour of the month, save the solution and reinitialize
    if day(uc_time) == 1 && hour(uc_time) == 0
        # save the solution only if final hour of last month has been solved
        if length(uc_sol["Time"]) > 0 && uc_sol["Time"][end] == uc_time - Hour(1)
            uc_sol_file = joinpath(result_dir, master_folder, POLICY, uc_folder, "UC_$(Date(uc_time - Month(1))).json")
            ed_sol_file = joinpath(result_dir, master_folder, POLICY, ed_folder, "ED_$(Date(uc_time - Month(1))).json")
            @info "Saving the solutions to $(uc_sol_file) and $(ed_sol_file)"
            write_json(uc_sol_file, uc_sol)
            write_json(ed_sol_file, ed_sol)
        end

        @info "Reinitialize the solution"
        uc_sol = init_solution_uc(UCsys)
        ed_sol = init_ed_solution(EDsys)
    end

    one_iter = @elapsed begin
    @info "Solving UC model at $(uc_time)"
    one_uc_time = @elapsed begin
    if init_fr_ED_flag || init_fr_file_flag 
        init_fr_file_flag = false
        init_fr_ED_flag = false
    else
        UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
    end
    uc_model = stochastic_uc(UCsys, Gurobi.Optimizer, VOLL; init_value = UC_init_value, theta = theta,
                        start_time = uc_time, scenario_count = scenario_cnt, horizon = uc_horizon)
    end
    @info "$(POLICY)-UC model at $(uc_time) is solved in $(one_uc_time) seconds"
    # Get commitment status that will be passed to ED
    uc_status = _get_binary_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
    uc_op_price = get_uc_op_price(UCsys, uc_model)
    one_hour_ed_time = @elapsed begin
    # initiate empty OrderedDict ed_hour_sol
    ed_hour_sol = init_ed_hour_solution(EDsys)
    for i in 1:12
        @info "Running length $(length(ed_hour_sol["LMP"]))"
        ed_time = uc_time + Minute(5*(i-1))
        @info "Solving ED model at $(ed_time)"
        ED_init_value = _get_init_value_for_ED(EDsys, uc_status; UC_init_value = UC_init_value, ed_model = ed_model)
        ed_model = stochastic_ed(EDsys, Gurobi.Optimizer, VOLL; uc_op_price = uc_op_price, init_value = ED_init_value, scenario_count = scenario_cnt, theta = theta, start_time = ed_time, horizon = ed_horizon)
        ed_hour_sol = get_ed_hour_solution(EDsys, ed_model, ed_hour_sol)
        if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
            @warn "ED model at $(ed_time) is with status $(primal_status(ed_model))"
            break
        end
    end

    if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        break
    end
    end
    @info "$(POLICY)-ED model at $(uc_time) is solved in $(one_hour_ed_time) seconds"
    uc_sol = get_solution_uc(UCsys, uc_model, ed_hour_sol, uc_sol)
    @info "$(POLICY)-UC solution is updated"

    ed_sol = merge_ed_solution(ed_sol, ed_hour_sol)
    @info "$(POLICY)-ED solution is merged"
end
    @info "One iteration takes $(one_iter) seconds"
end

# # save the solution
# save_date = Date(year(uc_time), month(uc_time), 1)
# uc_sol_file = joinpath(result_dir, master_folder, POLICY, uc_folder, "UC_$(save_date).json")
# ed_sol_file = joinpath(result_dir, master_folder, POLICY, ed_folder, "ED_$(save_date).json")
# @info "Saving the solutions to $(uc_sol_file) and $(ed_sol_file)"
# write_json(uc_sol_file, uc_sol)
# write_json(ed_sol_file, ed_sol)
@info "Running rolling horizon $(POLICY) is completed at $(uc_time)"
@info "Current time is $(now())"

# write_model_txt(uc_model, "uc_model", result_dir)
