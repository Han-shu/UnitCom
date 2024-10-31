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
    "SB": Stochastic benchmark, contingency reserve only, no new reserve requirement
    "MF": 50 percentile forecast
    "BNR": Biased forecast (theta = 11)
    "WF": Worst forecast (highest net load case, theta = 100)
    "MLF": Most likely forecast (theta = 1 without ranking)
    "FR": Fixed reserve requirement
    "DR": Dynamic reserve requirement
=#

# Specify the policy and running date
POLICY = "WF"
run_date =Date(2024,10,5) # or Specify running date Date(2024,5,1)
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
if POLICY == "SB" || POLICY == "MLF" # Stochastic model or Most likely forecast
    @info "Adding scenarios time series data for UC"
    add_scenarios_time_series!(UCsys; min5_flag = false, rank_netload = false)
    @info "Adding scenarios time series data for ED"
    add_scenarios_time_series!(EDsys; min5_flag = true, rank_netload = false)
else # Deterministic model
    @info "Adding quantile time series data for UC"
    add_scenarios_time_series!(UCsys; min5_flag = false, rank_netload = true)
    @info "Adding quantile time series data for ED"
    add_scenarios_time_series!(EDsys; min5_flag = true, rank_netload = true)
end

# Compute fixed reserve requirement for FR policy
reserve_requirement = Dict()
if POLICY == "FR"
    reserve_requirement["UC"] = comp_fixed_reserve_requirement(theta; min5_flag = false)
    reserve_requirement["ED"] = comp_fixed_reserve_requirement(theta; min5_flag = true)
end

# Run a apecific time
uc_time = DateTime(2019,1,12,10)
file_time = DateTime(2019, month(uc_time),1)
uc_sol_file = joinpath(result_dir, master_folder, uc_folder, "UC_$(Date(file_time)).json")
ed_sol_file = joinpath(result_dir, master_folder, ed_folder, "ED_$(Date(file_time)).json")
uc_sol = read_json(uc_sol_file)
ed_sol = read_json(ed_sol_file)

@info "Solving UC model at $(uc_time)"
UC_init_value = _get_init_value_for_UC(UCsys; uc_sol = uc_sol, ed_sol = ed_sol, init_fr_file_flag = true, init_fr_file_time = uc_time-Hour(1))
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                    start_time = uc_time, scenario_count = scenario_cnt, horizon = uc_horizon)
@info "$(POLICY)-UC model at $(uc_time) is solved" # in $(one_uc_time) seconds"
# Get commitment status that will be passed to ED
uc_status = _get_binary_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
uc_op_price = get_uc_op_price(UCsys, uc_model)

ed_hour_sol = init_ed_hour_solution(EDsys)
ed_model = nothing

for i in 1:12
    global ed_model, ed_hour_sol
    @info "Running length $(length(ed_hour_sol["LMP"]))"
    ed_time = uc_time + Minute(5*(i-1))
    if ed_time == DateTime(2019,1,12,10,45)
        break
    end
    @info "Solving ED model at $(ed_time)"
    ED_init_value = _get_init_value_for_ED(EDsys, uc_status; UC_init_value = UC_init_value, ed_model = ed_model)
    ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; uc_op_price = uc_op_price, init_value = ED_init_value, scenario_count = scenario_cnt, theta = theta, start_time = ed_time, horizon = ed_horizon)
    ed_hour_sol = get_ed_hour_solution(EDsys, ed_model, ed_hour_sol)
    if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        @warn "ED model at $(ed_time) is with status $(primal_status(ed_model))"
        break
    end
end

@info "$(POLICY)-ED model at $(uc_time) is solved."
uc_sol = get_solution_uc(UCsys, uc_model, ed_hour_sol, uc_sol)
@info "$(POLICY)-UC solution is updated"

