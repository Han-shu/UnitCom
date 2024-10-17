using Plots, Dates, JuMP

include("../src/functions.jl")

function get_gen_names_by_type()
    sys = build_ny_system(base_power = 100)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fast_gen_names = []
    nuclear_gen_names = []
    for g in thermal_gen_names
        generator = get_component(ThermalGen, sys, g)
        time_limits = get_time_limits(get_component(ThermalGen, sys, g))
        if time_limits[:up] <= 1
            push!(fast_gen_names, g)
        end
        if generator.fuel == ThermalFuels.NUCLEAR
            push!(nuclear_gen_names, g)
        end
    end
    return fast_gen_names, nuclear_gen_names, thermal_gen_names
end

function extract_LMP(res_dir::AbstractString, POLICY::AbstractString, run_date)::Tuple{Array{Float64}, Array{Float64}}
    uc_LMP, ed_LMP = [], []
    file_date = Dates.Date(2018,12,1)
    path_dir = joinpath(res_dir, "Master_$(POLICY)")
    @assert isdir(path_dir) error("Directory not found for $(POLICY)")
    while true
        file_date += Dates.Month(1)
        uc_file = joinpath(path_dir, "$(POLICY)_$(run_date)", "UC_$(file_date).json")
        ed_file = joinpath(path_dir, "ED_$(POLICY)_$(run_date)", "ED_$(file_date).json")
        if !isfile(uc_file) || !isfile(ed_file)
            break
        end
        @info "Extracting LMP for $(POLICY) with date $(file_date)"
        uc_solution = read_json(uc_file)
        ed_solution = read_json(ed_file)
        append!(uc_LMP, uc_solution["Hourly average LMP"])
        for i in ed_solution["LMP"]
            append!(ed_LMP, i)
        end
    end
    return uc_LMP, ed_LMP
end



function calc_cost_fr_uc_sol(POLICY::String, res_dir::String, run_date::Dates.Date, file_date::Dates.Date; extract_len::Union{Nothing, Int64} = nothing)
    uc_file = joinpath(res_dir, "Master_$(POLICY)", "$(POLICY)_$(run_date)", "UC_$(file_date).json")
    uc_sol = read_json(uc_file)
    if isnothing(extract_len)
        extract_len = length(uc_sol["Time"])
    end
    load_curtailment = sum(uc_sol["Curtailment"]["load"][1:extract_len])
    wind_curtailment = sum(uc_sol["Curtailment"]["wind"][1:extract_len])
    solar_curtailment = sum(uc_sol["Curtailment"]["solar"][1:extract_len])
    
    # Build System and collect cost information
    sys = build_ny_system(base_power = 100)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    GenFuelCosts = 0
    GenIntegerCosts = 0
    Gen_cost_dict = Dict()
    Gen_profit = DefaultDict{String, Float64}(0)
    for g in thermal_gen_names
        genfuel_cost = variable_cost[g]*sum(uc_sol["Generator Dispatch"][g][1:extract_len]) + fixed_cost[g]*sum(uc_sol["Commitment status"][g][1:extract_len])
        geninteger_cost = startup_cost[g]*sum(uc_sol["Start up"][g][1:extract_len]) + shutdown_cost[g]*sum(uc_sol["Shut down"][g][1:extract_len]) 
        Gen_cost_dict[g] = genfuel_cost + geninteger_cost
        GenFuelCosts += genfuel_cost
        GenIntegerCosts += geninteger_cost
        Gen_profit[g] -= genfuel_cost + geninteger_cost
    end
    VOLL = 5000
    load_curtailment_penalty = load_curtailment*VOLL
    TotalCosts = GenFuelCosts + GenIntegerCosts + load_curtailment_penalty
    
    Gen_energy_revenue = Dict()
    Gen_reserve_revenue = Dict()
    for key in keys(uc_sol["Energy Revenues"])
        Gen_energy_revenue[key] = sum(uc_sol["Energy Revenues"][key][1:extract_len]) 
        Gen_reserve_revenue[key] = sum(uc_sol["Reserve Revenues"][key][1:extract_len]) 
        Gen_profit[key] += Gen_energy_revenue[key] + Gen_reserve_revenue[key]
    end
    for key in keys(uc_sol["Other Profits"])
        Gen_energy_revenue[key] = sum(uc_sol["Other Profits"][key][1:extract_len])
        Gen_profit[key] += Gen_energy_revenue[key]
    end
    println("Policy: $(POLICY), Run date: $(run_date)")
    println("Load curtailment: $(load_curtailment), Wind curtailment: $(wind_curtailment), Solar curtailment: $(solar_curtailment)")
    println("Generation fuel costs: $(GenFuelCosts), Generation integer costs: $(GenIntegerCosts)")
    println("Total cost: $(TotalCosts)")
    ans = OrderedDict("Generation fuel cost" => GenFuelCosts, "Generation integer cost"=> GenIntegerCosts, "Load curtailment penalty" => load_curtailment_penalty, "Total cost" => TotalCosts, 
                    "Load curtailment" => load_curtailment, "Generation energy revenue" => sum(values(Gen_energy_revenue)), "Generation reserve revenue" => sum(values(Gen_reserve_revenue)))
    return ans, Gen_energy_revenue, Gen_reserve_revenue, Gen_cost_dict, Gen_profit
end

res_dir = "/Users/hanshu/Desktop/Price_formation/Result"
run_dates = Dict("DR" => Dates.Date(2024,10,17))
                # "SB" => Dates.Date(2024,10,2), 
#                 "PF" => Dates.Date(2024,10,8),
#                 "NR" => Dates.Date(2024,10,4), 
#                 "BNR" => Dates.Date(2024,10,4), 
#                 "WF" => Dates.Date(2024,10,5), 
                

uc_sol = read_json("/Users/hanshu/Desktop/Price_formation/Result/Master_SB/SB_2024-10-02/UC_2019-01-01.json")
extract_len = length(uc_sol["Time"])

Costs = Dict()
GenEnergyRevenues = Dict()
GenReserveRevenues = Dict()
GenProfits = Dict()
GenCosts = Dict()
for POLICY in collect(keys(run_dates))
    run_date = run_dates[POLICY]
    file_date = Dates.Date(2019,1,1)
    ans, Gen_energy_revenue, Gen_reserve_revenue, Gen_cost_dict, Gen_profit = calc_cost_fr_uc_sol(POLICY, res_dir, run_date, file_date, extract_len = extract_len)
    Costs[POLICY] = ans
    GenEnergyRevenues[POLICY] = Gen_energy_revenue
    GenReserveRevenues[POLICY] = Gen_reserve_revenue
    GenProfits[POLICY] = Gen_profit
    GenCosts[POLICY] = gen_costs
end

fast_gen_names, nuclear_gen_names, thermal_gen_names = get_gen_names_by_type()

fast_gen_profits = Dict(POLICY => sum(GenProfits[POLICY][g] for g in fast_gen_names) for POLICY in collect(keys(run_dates)))
nuclear_gen_profits = Dict(POLICY => sum(GenProfits[POLICY][g] for g in nuclear_gen_names) for POLICY in collect(keys(run_dates)))
thermal_gen_profits = Dict(POLICY => sum(GenProfits[POLICY][g] for g in thermal_gen_names) for POLICY in collect(keys(run_dates)))
storage_profits = Dict(POLICY => sum(GenProfits[POLICY][b] for b in ["BA", "PH"]) for POLICY in collect(keys(run_dates)))
all_gen_profits = Dict(POLICY => sum(GenProfits[POLICY][g] for g in keys(GenProfits[POLICY])) for POLICY in collect(keys(run_dates)))

df = DataFrame(POLICY = collect(keys(run_dates)), 
                TotalCosts = [Costs[POLICY]["Total cost"] for POLICY in collect(keys(run_dates))],
                Load_curtailment = [Costs[POLICY]["Load curtailment"] for POLICY in collect(keys(run_dates))],
                Generation_fuel_cost = [Costs[POLICY]["Generation fuel cost"] for POLICY in collect(keys(run_dates))],
                Generation_integer_cost = [Costs[POLICY]["Generation integer cost"] for POLICY in collect(keys(run_dates))],
                Load_curtailment_penalty = [Costs[POLICY]["Load curtailment penalty"] for POLICY in collect(keys(run_dates))],
                Generation_energy_revenue = [Costs[POLICY]["Generation energy revenue"] for POLICY in collect(keys(run_dates))],
                Generation_reserve_revenue = [Costs[POLICY]["Generation reserve revenue"] for POLICY in collect(keys(run_dates))],
                Fast_gen_profits = [fast_gen_profits[POLICY] for POLICY in collect(keys(run_dates))],
                Nuclear_gen_profits = [nuclear_gen_profits[POLICY] for POLICY in collect(keys(run_dates))],
                Storage_profits = [storage_profits[POLICY] for POLICY in collect(keys(run_dates))],
                All_gen_profits = [all_gen_profits[POLICY] for POLICY in collect(keys(run_dates))])

                
# thermal_gen_names = get_name.(get_components(ThermalGen, sys))
# fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
# startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
# shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
# variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

# uc_sol["Start up"]["Hellgate 1"]
# sum(uc_sol["Shut down"]["Hellgate 1"])
# gen_name = "Vernon Blvd 3"
# sum(uc_sol["Commitment status"][gen_name])
# integer_cost = fixed_cost[gen_name]*sum(uc_sol["Commitment status"][gen_name]) + startup_cost[gen_name]*sum(uc_sol["Start up"][gen_name]) + shutdown_cost[gen_name]*sum(uc_sol["Shut down"][gen_name])
# integer_cost + variable_cost[gen_name]*sum(uc_sol["Generator Dispatch"][gen_name])

# gen = get_component(ThermalGen, sys, "Hellgate 1")
# sys = build_ny_system(base_power = 100)
# thermal_gen_names = get_name.(get_components(ThermalGen, sys))
# fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
# startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
# shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
# variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)


# integer_cost = Dict()
# for g in thermal_gen_names
#     # genfuel_cost += variable_cost[g]*sum(uc_sol["Generator Dispatch"][g])
#     geninteger_cost = fixed_cost[g]*sum(uc_sol["Commitment status"][g])
#             + startup_cost[g]*sum(uc_sol["Start up"][g]) + shutdown_cost[g]*sum(uc_sol["Shut down"][g]) 
#     integer_cost[g] = geninteger_cost
# end


# policies = collect(keys(run_dates))
# hour_LMPS = Dict{String, Vector{Float64}}()
# min5_LMPS = Dict{String, Vector{Float64}}()
# for POLICY in policies
#     uc_LMP, ed_LMP = extract_LMP(res_dir, POLICY, run_dates[POLICY])
#     hour_LMPS[POLICY] = uc_LMP
#     min5_LMPS[POLICY] = ed_LMP
# end

# using Statistics
# for key in keys(hour_LMPS)
#     println("Policy: $(key), Average LMP: $(mean(hour_LMPS[key]))")
# end

# POLICY = "WF"
# run_date = run_dates[POLICY]    
# file_date = Dates.Date(2019,1,1)
# path_dir = joinpath(res_dir, "Master_$(POLICY)")
# @assert isdir(path_dir) error("Directory not found for $(POLICY)")
# uc_file = joinpath(path_dir, "$(POLICY)_$(run_date)", "UC_$(file_date).json")
# ed_file = joinpath(path_dir, "ED_$(POLICY)_$(run_date)", "ED_$(file_date).json")
# @info "Extracting LMP for $(POLICY) with date $(file_date)"
# uc_solution = read_json(uc_file)
# ed_solution = read_json(ed_file)

# for t in 1:length(ed_solution["Time"])
#     if mean(ed_solution["LMP"][t]) > 60
#         println("Time: $(ed_solution["Time"][t]), LMP: $(ed_solution["LMP"][t])")
#     end
# end