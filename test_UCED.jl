include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")

# Test UC-ED
# 1. LMP is 0 in ED
# 2. Timescale to calculate price (5 minutes)

theta = nothing # nothing or set between 1 ~ 49 (Int)
scenario_count = 10
uc_horizon = 36
ed_horizon = 12
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
ed_sol_file = joinpath(result_dir, "ED_sol_$(Dates.today()).json")
uc_sol_file = joinpath(result_dir, "UC_sol_$(Dates.today()).json")

UCsys = build_ny_system(base_power = 100)
add_scenarios_time_series_UC!(UCsys)
EDsys = build_ny_system(base_power = 100)
add_scenarios_time_series_ED!(EDsys)

init_time = DateTime(2019,1,1)
uc_model, ed_model = nothing, nothing
uc_sol = init_solution_uc(UCsys)

t = 1
uc_time = init_time + Hour(1)*(t-1)
UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                    start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)
# Get commitment status that will be passed to ED
uc_status = _get_commitment_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)
ed_sol = init_solution_ed(EDsys)
i = 1
ed_time = uc_time + Minute(5*(i-1))
@info "Solving ED model at $(ed_time)"
ED_init_value = _get_init_value_for_ED(EDsys, uc_status; ed_model = ed_model, UC_init_value = UC_init_value)
ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)

for i in 1:12
    global ed_model, ed_sol
    @info "Running length $(length(ed_sol["LMP"]))"
    ed_time = uc_time + Minute(5*(i-1))
    @info "Solving ED model at $(ed_time)"
    ED_init_value = _get_init_value_for_ED(EDsys, ug_t0; ed_model = ed_model, UC_init_value = UC_init_value)
    ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)
    ed_sol = get_solution_ed(EDsys, ed_model, ed_sol)
end
write_json(ed_sol_file, ed_sol)

uc_sol = get_solution_uc(UCsys, uc_model, ed_sol, uc_sol)
write_json(uc_sol_file, uc_sol)

uc_model, ed_model = nothing, nothing
UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
uc_model = stochastic_uc(UCsys, Gurobi.Optimizer; init_value = UC_init_value, theta = theta,
                    start_time = uc_time, scenario_count = scenario_count, horizon = uc_horizon)
ug_t0 = _get_commitment_status_for_ED(uc_model, get_name.(get_components(ThermalGen, UCsys)); CoverHour = 2)

ed_time = uc_time + Minute(5)*0
ED_init_value = _get_init_value_for_ED(EDsys, ug_t0; ed_model = ed_model, UC_init_value = UC_init_value)
ed_model = stochastic_ed(EDsys, Gurobi.Optimizer; init_value = ED_init_value, theta = theta, start_time = ed_time, horizon = ed_horizon)

LMP = ones(10,12)
for s in 1:10, t in 1:12
    LMP[s,t] = dual(ed_model[:eq_power_balance][s,t])
end

LMP == zeros(10,12) # LMP is 0 in ED


ed_model = stochastic_ed(EDsys, Gurobi.Optimizer, theta = theta, start_time = DateTime(2019, 1, 1,10,20,0))
LMP, Pspin10, Pres10, Pres30 = ones(10,12), ones(10,12), ones(10,12), ones(10,12)
for s in 1:10, t in 1:12
    LMP[s,t] = dual(ed_model[:eq_power_balance][s,t])
    Pspin10[s,t] = dual(ed_model[:eq_reserve_spin10][s,t])
    Pres10[s,t] = dual(ed_model[:eq_reserve_10][s,t])
    Pres30[s,t] = dual(ed_model[:eq_reserve_30][s,t])
end






uc_model, ed_model = nothing, nothing
UC_init_value = _get_init_value_for_UC(UCsys; uc_model = uc_model, ed_model = ed_model)  
thermal_gen_names = get_name.(get_components(ThermalGen, UCsys))
num_commit1, num_commit2 = 0, 0
ug_t0 = UC_init_value.ug_t0
for g in thermal_gen_names
    println("$g commitment status: ", ug_t0[g])
    if abs(ug_t0[g][1] - ug_t0[g][2]) > 1e-6
        num_commit1 += 1
    end
end
println("Number of committed generators at 1: ", num_commit1)
println("Number of committed generators at 2: ", num_commit2)
ug_t0["Northport 4"]

ug_t0, Pg_t0, eb_t0 = _init_fr_ed_model(UCsys)
model = stochastic_ed(EDsys, Gurobi.Optimizer, start_time = DateTime(2019, 1, 1, 0, 5, 0))
gen_pg = OrderedDict(g => ones(10,24) for g in thermal_gen_names)
for g in thermal_gen_names
    for s in 1:10, t in 1:24
        gen_pg[g][s,t] = value(model[:pg][g,s,t])
    end
end

for g in thermal_gen_names
    if gen_pg[g] != zeros(10,24)
        println("$g has non-zero power output")
    end
end

start_time = DateTime(2019, 1, 1, 0, 0, 0)
idx = 1
for t in 1:12
    if minute(start_time + Minute(5)*(t-1)) == 0
        println("Time: ", start_time + Minute(5)*(t-1))
        println("Time index: ", t)
        println("Index: ", idx)
        idx += 1
    end
end

minute(DateTime(2019, 1, 1, 0, 5, 0)) == 0