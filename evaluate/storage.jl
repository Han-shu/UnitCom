# Storage maximize profit

using JuMP, Gurobi, Dates

function storage_max_profit_model(sys, b::AbstractString, LMP::Vector{Any}, reserve_prices::Dict{String, Vector{Any}})
    
    storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
    eb_t0 = Dict(x => get_initial_energy(get_component(PSY.GenericBattery, sys, x)) for x in storage_names)
    eb_lim = Dict(x => get_state_of_charge_limits(get_component(PSY.GenericBattery, sys, x)) for x in storage_names)
    η = Dict(x => get_efficiency(get_component(PSY.GenericBattery, sys, x)) for x in storage_names)
    kb_charge_max = Dict(x => get_input_active_power_limits(get_component(PSY.GenericBattery, sys, x))[:max] for x in storage_names)
    kb_discharge_max = Dict(x => get_output_active_power_limits(get_component(PSY.GenericBattery, sys, x))[:max] for x in storage_names)
    spin_reserve_types = ["10S", "30S", "60S"]
    duration = 1/12
    time_steps = 1:length(LMP)

    model = Model(Gurobi.Optimizer)
    set_silent(model)
    @variable(model, kb_charge[t in time_steps], lower_bound = 0, upper_bound = kb_charge_max[b])
    @variable(model, kb_discharge[t in time_steps], lower_bound = 0, upper_bound = kb_discharge_max[b])
    @variable(model, eb[t in time_steps], lower_bound = eb_lim[b].min, upper_bound = eb_lim[b].max)
    @variable(model, battery_reserve[r in spin_reserve_types, t in time_steps], lower_bound = 0)

    # Sustainable time limits for reserves
    @constraint(model, eq_battery_res[t in time_steps], 
        (1/η[b].out)*(battery_reserve["10S",t]/6 + battery_reserve["30S",t]/2 + battery_reserve["60S",t]*4) <= eb[t] - eb_lim[b].min)
    # Battery discharge
    @constraint(model, battery_discharge[t in time_steps], 
                    kb_discharge[t] + battery_reserve["10S",t] + battery_reserve["30S",t] + battery_reserve["60S",t] <= kb_discharge_max[b])
    # Storage energy update
    @constraint(model, eq_storage_energy[t in time_steps],
        eb[t] == (t==1 ? eb_t0[b] : eb[t-1]) + η[b].in * kb_charge[t]*duration - (1/η[b].out) * kb_discharge[t]*duration)

    @objective(model, Max, sum((kb_discharge[t]*duration - kb_charge[t]*duration)*LMP[t] + sum(battery_reserve[r,t]*duration*reserve_prices[r][t] for r in spin_reserve_types) for t in time_steps))

    optimize!(model)
    
    return model
end

function extract_prices(POLICY::AbstractString, run_date::Date)
    master_folder, uc_folder, ed_folder = policy_model_folder_name(POLICY, run_date)
    if POLICY == "SB"
        filedates = [Date(2019, 1, 10), Date(2019, 1, 20), Date(2019, 1, 31)]
    else
        filedates = [Date(2019, 1, 31)]
    end
    LMP = []
    reserve_prices = Dict("10S" => [], "30S" => [], "60S" => [])
    for filedate in filedates
        # uc_sol_file = joinpath(result_dir, master_folder, POLICY, uc_folder, "UC_$(filedate).json")
        # uc_sol = read_json(uc_sol_file)
        # append!(LMP, uc_sol["Hourly average LMP"])
        # append!(reserve_prices["10S"], uc_sol["Hourly average reserve price 10Spin"])
        # append!(reserve_prices["30S"], uc_sol["Hourly average reserve price 30Total"])
        # append!(reserve_prices["60S"], uc_sol["Hourly average reserve price 60Total"])
        ed_sol_file = joinpath(result_dir, master_folder, POLICY, ed_folder, "ED_$(filedate).json")
        ed_sol = read_json(ed_sol_file)
        for i in 1:length(ed_sol["Time"])
            append!(LMP, ed_sol["LMP"][i])
            append!(reserve_prices["10S"], ed_sol["Reserve price 10Spin"][i])
            append!(reserve_prices["30S"], ed_sol["Reserve price 30Total"][i])
            append!(reserve_prices["60S"], ed_sol["Reserve price 60Total"][i])
        end
    end
    return LMP, reserve_prices
end

function calc_policy_storage_profit(sys, POLICY::AbstractString, run_date::Date)
    duration = 1/12
    LMP, reserve_prices = extract_prices(POLICY, run_date)
    BA_model = storage_max_profit_model(sys, "BA", LMP, reserve_prices)
    PH_model = storage_max_profit_model(sys, "PH", LMP, reserve_prices)
    println("BA: ", objective_value(BA_model))
    println("PH: ", objective_value(PH_model))
    ba_energy_revenue = sum((value(BA_model[:kb_discharge][t]) - value(BA_model[:kb_charge][t]))*LMP[t]*duration for t in 1:length(LMP))
    ph_energy_revenue = sum((value(PH_model[:kb_discharge][t]) - value(PH_model[:kb_charge][t]))*LMP[t]*duration for t in 1:length(LMP))
    ba_reserve_revenue = sum(value(BA_model[:battery_reserve][r,t])*reserve_prices[r][t]*duration for r in spin_reserve_types, t in 1:length(LMP))
    ph_reserve_revenue = sum(value(PH_model[:battery_reserve][r,t])*reserve_prices[r][t]*duration for r in spin_reserve_types, t in 1:length(LMP))
    ba_cycle = sum(value(BA_model[:kb_discharge][t]) for t in 1:length(LMP))/get_state_of_charge_limits(get_component(PSY.GenericBattery, sys, "BA"))[:max]
    ph_cycle = sum(value(PH_model[:kb_discharge][t]) for t in 1:length(LMP))/get_state_of_charge_limits(get_component(PSY.GenericBattery, sys, "PH"))[:max]
    discharge = Dict("BA" => [value(BA_model[:kb_discharge][t]) for t in 1:length(LMP)], "PH" => [value(PH_model[:kb_discharge][t]) for t in 1:length(LMP)])
    charge = Dict("BA" => [value(BA_model[:kb_charge][t]) for t in 1:length(LMP)], "PH" => [value(PH_model[:kb_charge][t]) for t in 1:length(LMP)])
    energy = Dict("BA" => [value(BA_model[:eb][t]) for t in 1:length(LMP)], "PH" => [value(PH_model[:eb][t]) for t in 1:length(LMP)])
    results = Dict("BA profit" => objective_value(BA_model), "PH profit" => objective_value(PH_model), "BA energy revenue" => ba_energy_revenue, "PH energy revenue" => ph_energy_revenue,
                    "BA reserve revenue" => ba_reserve_revenue, "PH reserve revenue" => ph_reserve_revenue, "BA cycle" => ba_cycle, "PH cycle" => ph_cycle)
    return results, discharge, charge, energy
end

# Read history LMP
sys = build_ny_system(base_power = 100)
result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
run_date = Date(2024,12,3)
# policies = ["SB", "PF", "MF", "BF", "WF", "DR", "DR30"]
policies = ["PF"]

# ba_profits, ph_profits = Dict(), Dict()
# ba_energy_revenues, ph_energy_revenues = Dict(), Dict()
# ba_reserve_revenues, ph_reserve_revenues = Dict(), Dict()
# ba_cycles, ph_cycles = Dict(), Dict()

results = Dict()
df = DataFrame()
for POLICY in policies
    println("Policy: ", POLICY)
    result, discharge, charge, energy = calc_policy_storage_profit(sys, POLICY, run_date)
    results[POLICY] = result
    df[!, "$(POLICY)_BA_energy"] = energy["BA"]
    df[!, "$(POLICY)_PH_energy"] = energy["PH"]
end

CSV.write(joinpath(result_dir, "$(run_date)", "storage_energy.csv"), df)

# df = DataFrame(POLICY = policies, BA_profit = [ba_profits[p] for p in policies], PH_profit = [ph_profits[p] for p in policies],
#         BA_energy_revenue = [ba_energy_revenues[p] for p in policies], PH_energy_revenue = [ph_energy_revenues[p] for p in policies],
#         BA_reserve_revenue = [ba_reserve_revenues[p] for p in policies], PH_reserve_revenue = [ph_reserve_revenues[p] for p in policies],
#         BA_cycle = [ba_cycles[p] for p in policies], PH_cycle = [ph_cycles[p] for p in policies])