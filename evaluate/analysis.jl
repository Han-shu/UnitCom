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
    solar_capacity = 766 #522.7
    wind_capacity = 3498 #1983 #2736
    hydro_capacity = 4800

    storage_names = get_name.(get_components(GenericBattery, sys))
    kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
    return Dict("Fast" => fast_gen_capacity, "Nuclear" => nuclear_gen_capacity, "Thermal" => thermal_gen_capacity,
                "BA" => kb_charge_max["BA"], "PH" => kb_charge_max["PH"], "wind" => wind_capacity, "solar" => solar_capacity, "hydro" => hydro_capacity)
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


function _get_filedates(POLICY, _month)
    # Dates.Date(2019,2,28), Dates.Date(2019,3,31), 
        #     Dates.Date(2019,4,30), Dates.Date(2019,5,31), Dates.Date(2019,6,30), 
        #     Dates.Date(2019,7,31), Dates.Date(2019,8,31), Dates.Date(2019,9,30), 
        #     Dates.Date(2019,10,31), Dates.Date(2019,11,30), Dates.Date(2019,12,29)]
    if POLICY == "SB"
        if _month == "Feb"
            filedates = [Dates.Date(2019,2,10), Dates.Date(2019,2,20), Dates.Date(2019,2,28)]
        elseif _month == "Aug"
            filedates = [Dates.Date(2019,8,10), Dates.Date(2019,8,20), Dates.Date(2019,8,31)] 
        else
            error("Month not supported")
        end
    else
        if _month == "Feb"
            filedates = [Dates.Date(2019,2,28)]
        elseif _month == "Aug"
            filedates = [Dates.Date(2019,8,31)]
        else
            error("Month not supported")
        end
    end
    return filedates
end

function calc_cost_fr_uc_sol(POLICY::String, res_dir::String, run_date::Dates.Date; _month, extract_len::Union{Nothing, Int64} = nothing)
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
    wind_generation = 0
    solar_generation = 0

    GenFuelCosts = 0
    GenIntegerCosts = 0
    Gen_cost_dict = DefaultDict{String, Float64}(0)
    Gen_profit = DefaultDict{String, Float64}(0)
    Gen_energy_revenue = DefaultDict{String, Float64}(0)
    Gen_reserve_revenue = DefaultDict{String, Float64}(0)
    
    filedates = _get_filedates(POLICY, _month)
    for filename in filedates
        uc_file =  joinpath(path_dir, "UC_$(filename).json")
        println("Extracting cost from $(uc_file)")
        uc_sol = read_json(uc_file)
        extract_len = length(uc_sol["Time"])

        load_curtailment += sum(uc_sol["Load Curtailment"][1:extract_len])
        wind_generation += sum(uc_sol["Renewable Generation"]["wind"][1:extract_len])
        solar_generation += sum(uc_sol["Renewable Generation"]["solar"][1:extract_len])

        for g in thermal_gen_names
            genfuel_cost = variable_cost[g]*sum(uc_sol["Generator Dispatch"][g][1:extract_len]) + fixed_cost[g]*sum(uc_sol["Commitment status"][g][1:extract_len])
            geninteger_cost = startup_cost[g]*sum(uc_sol["Start up"][g][1:extract_len]) + shutdown_cost[g]*sum(uc_sol["Shut down"][g][1:extract_len]) 
            Gen_cost_dict[g] += genfuel_cost + geninteger_cost
            Gen_profit[g] -= (genfuel_cost + geninteger_cost)
            GenFuelCosts += genfuel_cost
            GenIntegerCosts += geninteger_cost
        end
        
        for key in keys(uc_sol["Energy Revenues"])
            energy_revenue = sum(uc_sol["Energy Revenues"][key][1:extract_len])
            reserve_revenue = sum(uc_sol["Reserve Revenues"][key][1:extract_len])
            Gen_energy_revenue[key] +=  energy_revenue
            Gen_reserve_revenue[key] += reserve_revenue
            Gen_profit[key] += energy_revenue + reserve_revenue
        end

        for key in keys(uc_sol["Other Profits"])
            profit = sum(uc_sol["Other Profits"][key][1:extract_len])
            Gen_energy_revenue[key] += profit
            Gen_profit[key] += profit
        end
    end
    
    load_curtailment_penalty = load_curtailment*VOLL
    TotalCosts = GenFuelCosts + GenIntegerCosts + load_curtailment_penalty

    println("Run date: $(run_date), Policy: $(POLICY)")
    println("Load curtailment: $(load_curtailment)")
    print("Wind generation: $(wind_generation), Solar generation: $(solar_generation)")
    println("Generation fuel costs: $(GenFuelCosts), Generation integer costs: $(GenIntegerCosts)")
    println("Total cost: $(TotalCosts)")
    summary = OrderedDict("Generation fuel cost" => GenFuelCosts, "Generation integer cost"=> GenIntegerCosts, "Load curtailment penalty" => load_curtailment_penalty, "Total cost" => TotalCosts, 
                    "Load curtailment" => load_curtailment, "Generation energy revenue" => sum(values(Gen_energy_revenue)), "Generation reserve revenue" => sum(values(Gen_reserve_revenue)),
                    "Wind generation" => wind_generation, "Solar generation" => solar_generation)
    return summary, Gen_energy_revenue, Gen_reserve_revenue, Gen_cost_dict, Gen_profit
end

res_dir = "Result"
# INFORMS results run_date = Dates.Date(2024,10,18)

run_date = Dates.Date(2025,1,24) 
policies = ["SB", "PF", "MF", "BF", "WF", "DR60", "DR30"] 
_month = "Feb"
extract_len = nothing

Costs = OrderedDict()
GenEnergyRevenues = OrderedDict()
GenReserveRevenues = OrderedDict()
GenProfits = OrderedDict()
GenCosts = OrderedDict()
for POLICY in policies
    path_dir = joinpath(res_dir, "$(run_date)", POLICY)
    if !isdir(path_dir)
        println("Directory not found for $(POLICY)")
        continue
    end
    summary, Gen_energy_revenue, Gen_reserve_revenue, Gen_cost, Gen_profit = calc_cost_fr_uc_sol(POLICY, res_dir, run_date, _month = _month, extract_len = extract_len)
    Costs[POLICY] = summary
    GenEnergyRevenues[POLICY] = Gen_energy_revenue
    GenReserveRevenues[POLICY] = Gen_reserve_revenue
    GenProfits[POLICY] = Gen_profit
    GenCosts[POLICY] = Gen_cost
end

# for POLICY in policies
#     println("Policy: $(POLICY)")
#     println("BA energy revenue: $(GenEnergyRevenues[POLICY]["BA"]), BA reserve revenue: $(GenReserveRevenues[POLICY]["BA"])")
#     println("PH energy revenue: $(GenEnergyRevenues[POLICY]["PH"]), PH reserve revenue: $(GenReserveRevenues[POLICY]["PH"]) \n")
# end
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
                Wind_gen = [Costs[POLICY]["Wind generation"] for POLICY in policies],
                Solar_gen = [Costs[POLICY]["Solar generation"] for POLICY in policies])

df = leftjoin(revenue_df, cost_df, on = :POLICY)
CSV.write(joinpath(res_dir, "$(run_date)", _month * "_revenue_cost.csv"), df)

PerUnitProfit_df = DataFrame(POLICY = policies, 
                Fast = [PerUnitProfit[POLICY]["Fast"] for POLICY in policies],
                Nuclear = [PerUnitProfit[POLICY]["Nuclear"] for POLICY in policies],
                Thermal = [PerUnitProfit[POLICY]["Thermal"] for POLICY in policies],
                BA = [PerUnitProfit[POLICY]["BA"] for POLICY in policies],
                PH = [PerUnitProfit[POLICY]["PH"] for POLICY in policies],
                wind = [PerUnitProfit[POLICY]["wind"] for POLICY in policies],
                solar = [PerUnitProfit[POLICY]["solar"] for POLICY in policies],
                hydro = [PerUnitProfit[POLICY]["hydro"] for POLICY in policies])
CSV.write(joinpath(res_dir, "$(run_date)", _month * "_PerUnitProfit.csv"), PerUnitProfit_df)