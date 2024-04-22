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
global uc_model
uc_model, ed_model = nothing, nothing
# for i in 1:8760-uc_horizon+1

i = 1
uc_time = start_time + Hour(1)*(i-1)
@info "Solving UC model at $(uc_time)"
UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                    start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)

ug_t0 = _get_commitment_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
ed_model = nothing
for t in 1:12
    global ed_model
    ed_time = uc_time + Minute(5*(t-1))
    @info "Solving ED model at $(ed_time)"
    ED_init_value = _get_init_value_for_ED(EDsys, ug_t0; ed_model = ed_model, UC_init_value = UC_init_value)
    ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)
    if primal_status(ed_model) != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        @warn "ED model at $(ed_time) is not feasible"
        break
    end
end



# solution = get_solution_uc_t(system, model, solution)

# # save the solution
# write_json(solution_file, solution)

model = stochastic_ed(UCsys, Gurobi.Optimizer, start_time = DateTime(Date(2019, 1, 1)))
thermal_gen_names = get_name.(get_components(ThermalGen, UCsys))
Pg_t0 = Dict(g => get_active_power(get_component(ThermalGen, UCsys, g)) for g in thermal_gen_names)
get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
ramp_up = Dict(g => get_rmp_up_limit(get_component(ThermalGen, UCsys, g)) for g in thermal_gen_names)
ramp_dn = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, UCsys, g)) for g in thermal_gen_names)

