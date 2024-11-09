using Plots, Dates, JuMP

include("../src/functions.jl")
include("../NYGrid/build_ny_system.jl")
include("../NYGrid/manual_data_entries.jl")

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

function get_gen_capacity_by_type()
    sys = build_ny_system(base_power = 100)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fast_gen_capacity = 0
    nuclear_gen_capacity = 0
    thermal_gen_capacity = 0
    for g in thermal_gen_names
        generator = get_component(ThermalGen, sys, g)
        time_limits = get_time_limits(get_component(ThermalGen, sys, g))
        pg_lim = get_active_power_limits(get_component(ThermalGen, sys, g))
        if time_limits[:up] <= 1
            fast_gen_capacity += pg_lim.max
        end
        if generator.fuel == ThermalFuels.NUCLEAR
            nuclear_gen_capacity += pg_lim.max
        end
        thermal_gen_capacity += pg_lim.max
    end
    solar_capacity = 5227
    wind_capacity = 2736
    hydro_capacity = 4800
    # solar_capacity = get_active_power_limits(get_component(RenewableDispatch, sys, "solar")).max
    # wind_capacity = get_active_power_limits(get_component(RenewableDispatch, sys, "wind")).max
    # hydro_capacity = get_active_power_limits(get_component(HydroDispatch, sys, "hydro")).max

    return Dict("Fast" => fast_gen_capacity, "Nuclear" => nuclear_gen_capacity, "Thermal" => thermal_gen_capacity,
                "BA" => 1500, "PH" => 1170, "wind" => wind_capacity, "solar" => solar_capacity, "hydro" => hydro_capacity)
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



function calc_cost_fr_uc_sol(POLICY::String, res_dir::String, run_date::Dates.Date; extract_len::Union{Nothing, Int64} = nothing)
    path_dir = joinpath(res_dir, "$(run_date)", POLICY, "$(POLICY)_$(run_date)")
    filenames = readdir(path_dir)

    # Build System and collect cost information
    sys = build_ny_system(base_power = 100)
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalStandard, sys, g))) for g in thermal_gen_names)
    shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
    variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

    # Initialization
    load_curtailment = 0
    wind_curtailment = 0
    solar_curtailment = 0

    GenFuelCosts = 0
    GenIntegerCosts = 0
    Gen_cost_dict = DefaultDict{String, Float64}(0)
    Gen_profit = DefaultDict{String, Float64}(0)
    Gen_energy_revenue = DefaultDict{String, Float64}(0)
    Gen_reserve_revenue = DefaultDict{String, Float64}(0)

    filedates = [Dates.Date(2019,1,1), Dates.Date(2019,2,1)]
    for filename in filedates
        uc_file =  joinpath(path_dir, "UC_$(filename).json")
        println("Extracting cost from $(uc_file)")
        uc_sol = read_json(uc_file)
        extract_len = length(uc_sol["Time"])
        load_curtailment += sum(uc_sol["Curtailment"]["load"][1:extract_len])
        wind_curtailment += sum(uc_sol["Curtailment"]["wind"][1:extract_len])
        solar_curtailment += sum(uc_sol["Curtailment"]["solar"][1:extract_len])
    
        for g in thermal_gen_names
            genfuel_cost = variable_cost[g]*sum(uc_sol["Generator Dispatch"][g][1:extract_len]) + fixed_cost[g]*sum(uc_sol["Commitment status"][g][1:extract_len])
            geninteger_cost = startup_cost[g]*sum(uc_sol["Start up"][g][1:extract_len]) + shutdown_cost[g]*sum(uc_sol["Shut down"][g][1:extract_len]) 
            Gen_cost_dict[g] += genfuel_cost + geninteger_cost
            Gen_profit[g] -= (genfuel_cost + geninteger_cost)
            GenFuelCosts += genfuel_cost
            GenIntegerCosts += geninteger_cost
        end
        
        for key in keys(uc_sol["Energy Revenues"])
            Gen_energy_revenue[key] += sum(uc_sol["Energy Revenues"][key][1:extract_len]) 
            Gen_reserve_revenue[key] += sum(uc_sol["Reserve Revenues"][key][1:extract_len]) 
            Gen_profit[key] += Gen_energy_revenue[key] + Gen_reserve_revenue[key]
        end

        for key in keys(uc_sol["Other Profits"])
            Gen_energy_revenue[key] += sum(uc_sol["Other Profits"][key][1:extract_len])
            Gen_profit[key] += Gen_energy_revenue[key]
        end
    end
    
    load_curtailment_penalty = load_curtailment*VOLL
    TotalCosts = GenFuelCosts + GenIntegerCosts + load_curtailment_penalty

    println("Run date: $(run_date), Policy: $(POLICY)")
    println("Load curtailment: $(load_curtailment), Wind curtailment: $(wind_curtailment), Solar curtailment: $(solar_curtailment)")
    println("Generation fuel costs: $(GenFuelCosts), Generation integer costs: $(GenIntegerCosts)")
    println("Total cost: $(TotalCosts)")
    summary = OrderedDict("Generation fuel cost" => GenFuelCosts, "Generation integer cost"=> GenIntegerCosts, "Load curtailment penalty" => load_curtailment_penalty, "Total cost" => TotalCosts, 
                    "Load curtailment" => load_curtailment, "Generation energy revenue" => sum(values(Gen_energy_revenue)), "Generation reserve revenue" => sum(values(Gen_reserve_revenue)),
                    "Wind curtailment" => wind_curtailment, "Solar curtailment" => solar_curtailment)
    return summary, Gen_energy_revenue, Gen_reserve_revenue, Gen_cost_dict, Gen_profit
end

res_dir = "/Users/hanshu/Desktop/Price_formation/Result"
# INFORMS results run_date = Dates.Date(2024,10,18)

run_date = Dates.Date(2024,11,1)
policies = ["PF", "MF", "BF", "WF", "DR"]    
extract_len = nothing

Costs = OrderedDict()
GenEnergyRevenues = OrderedDict()
GenReserveRevenues = OrderedDict()
GenProfits = OrderedDict()
GenCosts = OrderedDict()
for POLICY in policies
    summary, Gen_energy_revenue, Gen_reserve_revenue, Gen_cost, Gen_profit = calc_cost_fr_uc_sol(POLICY, res_dir, run_date, extract_len = extract_len)
    Costs[POLICY] = summary
    GenEnergyRevenues[POLICY] = Gen_energy_revenue
    GenReserveRevenues[POLICY] = Gen_reserve_revenue
    GenProfits[POLICY] = Gen_profit
    GenCosts[POLICY] = Gen_cost
end

for POLICY in policies
    println("Policy: $(POLICY)")
    println("BA energy revenue: $(GenEnergyRevenues[POLICY]["BA"]), BA reserve revenue: $(GenReserveRevenues[POLICY]["BA"])")
    println("PH energy revenue: $(GenEnergyRevenues[POLICY]["PH"]), PH reserve revenue: $(GenReserveRevenues[POLICY]["PH"]) \n")
end
fast_gen_names, nuclear_gen_names, thermal_gen_names = get_gen_names_by_type()

fast_gen_profits = OrderedDict(POLICY => sum(GenProfits[POLICY][g] for g in fast_gen_names) for POLICY in policies)
nuclear_gen_profits = OrderedDict(POLICY => sum(GenProfits[POLICY][g] for g in nuclear_gen_names) for POLICY in policies)
thermal_gen_profits = OrderedDict(POLICY => sum(GenProfits[POLICY][g] for g in thermal_gen_names) for POLICY in policies)
storage_profits = OrderedDict(POLICY => sum(GenProfits[POLICY][b] for b in ["BA", "PH"]) for POLICY in policies)
all_gen_profits = OrderedDict(POLICY => sum(GenProfits[POLICY][g] for g in keys(GenProfits[POLICY])) for POLICY in policies)

types = ["Fast", "Nuclear", "Thermal", "BA", "PH", "wind", "solar", "hydro"]
capacity = get_gen_capacity_by_type()


PerUnitProfit = OrderedDict(POLICY => Dict() for POLICY in policies)
for POLICY in policies
    for t in types
        if t == "Fast"
            PerUnitProfit[POLICY][t] = fast_gen_profits[POLICY]/capacity[t]
        elseif t == "Nuclear"
            PerUnitProfit[POLICY][t] = nuclear_gen_profits[POLICY]/capacity[t]
        elseif t == "Thermal"
            PerUnitProfit[POLICY][t] = thermal_gen_profits[POLICY]/capacity[t]
        else
            PerUnitProfit[POLICY][t] = GenProfits[POLICY][t]/capacity[t]
        end
    end
end

revenue_df = DataFrame(POLICY = policies, 
                Gen_energy_revenue = [Costs[POLICY]["Generation energy revenue"] for POLICY in policies],
                Gen_reserve_revenue = [Costs[POLICY]["Generation reserve revenue"] for POLICY in policies],
                Fast_gen_profits = [fast_gen_profits[POLICY] for POLICY in policies],
                Nuclear_profits = [nuclear_gen_profits[POLICY] for POLICY in policies],
                Storage_profits = [storage_profits[POLICY] for POLICY in policies],
                Thermal_profits = [thermal_gen_profits[POLICY] for POLICY in policies],
                All_gen_profits = [all_gen_profits[POLICY] for POLICY in policies])

cost_df = DataFrame(POLICY = policies, 
                TotalCosts = [Costs[POLICY]["Total cost"] for POLICY in policies],
                Load_curtailment = [Costs[POLICY]["Load curtailment"] for POLICY in policies],
                Genfuel_cost = [Costs[POLICY]["Generation fuel cost"] for POLICY in policies],
                Gen_integer_cost = [Costs[POLICY]["Generation integer cost"] for POLICY in policies],
                Load_curtailment_penalty = [Costs[POLICY]["Load curtailment penalty"] for POLICY in policies],
                Wind_curt = [Costs[POLICY]["Wind curtailment"] for POLICY in policies],
                Solar_curt = [Costs[POLICY]["Solar curtailment"] for POLICY in policies])

df = leftjoin(revenue_df, cost_df, on = :POLICY)
# CSV.write(joinpath(res_dir, "$(run_date)", "revenue_cost.csv"), df)

PerUnitProfit_df = DataFrame(POLICY = policies, 
                Fast = [PerUnitProfit[POLICY]["Fast"] for POLICY in policies],
                Nuclear = [PerUnitProfit[POLICY]["Nuclear"] for POLICY in policies],
                Thermal = [PerUnitProfit[POLICY]["Thermal"] for POLICY in policies],
                BA = [PerUnitProfit[POLICY]["BA"] for POLICY in policies],
                PH = [PerUnitProfit[POLICY]["PH"] for POLICY in policies],
                wind = [PerUnitProfit[POLICY]["wind"] for POLICY in policies],
                solar = [PerUnitProfit[POLICY]["solar"] for POLICY in policies],
                hydro = [PerUnitProfit[POLICY]["hydro"] for POLICY in policies])
# CSV.write(joinpath(res_dir, "$(run_date)", "PerUnitProfit.csv"), PerUnitProfit_df)
      

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


# policies = policies
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