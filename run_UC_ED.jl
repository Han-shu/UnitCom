include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")

# Rolling horizon UC-ED

theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36
ed_horizon = 12
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
model_name = "UC-ED"
solution_file = joinpath(result_dir, "$(model_name)_sol_$(Dates.today()).json")

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

init_time = DateTime(2019,1,1)
uc_model, ed_model = nothing, nothing
uc_sol = init_solution_uc(UCsys)
for t in 1:8760-uc_horizon+1
    global uc_model, ed_model, uc_sol
    if t % 10 == 0
        write_json(solution_file, uc_sol)
    end
    if t > 16
        break
    end
    one_iter = @elapsed begin
    uc_time = init_time + Hour(1)*(t-1)
    @info "Solving UC model at $(uc_time)"
    one_uc_time = @elapsed begin
    UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
    uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                        start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)
    end
    @info "UC model at $(uc_time) is solved in $(one_uc_time) seconds"
    # Get commitment status that will be passed to ED
    ug_t0 = _get_commitment_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
    one_hour_ed_time = @elapsed begin
    ed_sol = init_solution_ed(EDsys)
    for i in 1:12
        @info "Running length $(length(ed_sol["LMP"]))"
        ed_time = uc_time + Minute(5*(i-1))
        @info "Solving ED model at $(ed_time)"
        ED_init_value = _get_init_value_for_ED(EDsys, ug_t0; ed_model = ed_model, UC_init_value = UC_init_value)
        ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)
        ed_sol = get_solution_ed(EDsys, ed_model, ed_sol)
        if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
            @warn "ED model at $(ed_time) is not feasible"
            break
        end
    end
    ed_sol_file = joinpath(result_dir, "ED_sol_$(uc_time).json")
    write_json(ed_sol_file, ed_sol)
    end
    @info "ED model at $(uc_time) is solved in $(one_hour_ed_time) seconds"
    uc_sol = get_solution_uc(UCsys, uc_model, ed_sol, uc_sol)
end
    @info "One iteration takes $(one_iter) seconds"
end

# # save the solution
write_json(solution_file, uc_sol)