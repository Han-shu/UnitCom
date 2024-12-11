include("../src/functions.jl")

using DataFrames, CSV

function year_gen_profit_in_model(model_name::String, uc_folder_dic::Dict{String, String})::DefaultDict{String, Float64}
    master_folder = "Master_"*model_name
    uc_folder = uc_folder_dic[model_name]
    ed_folder = "ED_"*uc_folder
    uc_path = joinpath(result_dir, master_folder, uc_folder)
    ed_path = joinpath(result_dir, master_folder, ed_folder)
    @assert ispath(uc_path) && ispath(ed_path)
    entries = readdir(uc_path)
    Gen_profit = DefaultDict{String, Float64}(0)
    for entry in entries
        if endswith(entry, ".json")
            uc_sol = read_json(joinpath(uc_path, entry))
            for key in keys(uc_sol["Generator profits"])
                Gen_profit[key] += sum(uc_sol["Generator profits"][key])
            end
            Gen_profit["Storage"] += sum(uc_sol["Storage profits"]["BA"])
        end
    end
    return Gen_profit
end

result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
model = ["STOCH", "AVG", "NLB"]
uc_folder_dic = Dict("STOCH"=> "S-UCED_2024-05-21", "AVG"=> "AVG-UCED_2024-05-15", "NLB"=> "NLB-10-UCED_2024-05-14")
Gen_profit_AVG = year_gen_profit_in_model(model[2], uc_folder_dic)
Gen_profit_NLB = year_gen_profit_in_model(model[3], uc_folder_dic)
df = DataFrame(Gen = [], AVG = [], NLB = [])
for key in keys(Gen_profit_AVG)
    push!(df, [key, Gen_profit_AVG[key], Gen_profit_NLB[key]])
end
#save the data frame to a csv file
CSV.write(joinpath(result_dir, "year_gen_profit.csv"), df)



function one_file_gen_profit_in_model(model_name::String, filename, length::Int, uc_folder_dic::Dict{String, String})::DefaultDict{String, Float64}
    master_folder = "Master_"*model_name
    uc_folder = uc_folder_dic[model_name]
    uc_path = joinpath(result_dir, master_folder, uc_folder)
    file = joinpath(uc_path, filename)
    @assert isfile(file)
    Gen_profit = DefaultDict{String, Float64}(0)
    uc_sol = read_json(file)
    for key in keys(uc_sol["Generator profits"])
        Gen_profit[key] += sum(uc_sol["Generator profits"][key][1:length])
    end
    Gen_profit["Storage"] += sum(uc_sol["Storage profits"]["BA"][1:length])
    return Gen_profit
end

filename = "UC_2019-01-01.json"
uc_sol = read_json("/Users/hanshu/Desktop/Price_formation/Result/Master_STOCH/S-UCED_2024-05-21/UC_2019-01-01.json")
extract_len = length(uc_sol["Time"])
file_gen_profit_STOCH = one_file_gen_profit_in_model("STOCH", filename, extract_len, uc_folder_dic)
file_gen_profit_AVG = one_file_gen_profit_in_model("AVG", filename, extract_len, uc_folder_dic)
file_gen_profit_NLB = one_file_gen_profit_in_model("NLB", filename, extract_len, uc_folder_dic)

file_df = DataFrame(Gen = [], STOCH = [], AVG = [], NLB = [])
for key in keys(file_gen_profit_STOCH)
    push!(file_df, [key, file_gen_profit_STOCH[key], file_gen_profit_AVG[key], file_gen_profit_NLB[key]])
end
#save the data frame to a csv file
CSV.write(joinpath(result_dir, "21days_gen_profit.csv"), file_df)


function year_cost_in_model(model_name::String, uc_folder_dic::Dict{String, String})
    master_folder = "Master_"*model_name
    uc_folder = uc_folder_dic[model_name]
    ed_folder = "ED_"*uc_folder
    uc_path = joinpath(result_dir, master_folder, uc_folder)
    ed_path = joinpath(result_dir, master_folder, ed_folder)
    @assert ispath(uc_path) && ispath(ed_path)
    entries = readdir(uc_path)
    Consumers_payment = []
    Total_cost = []
    Gen_profit = []
    Time = []
    for entry in entries
        if endswith(entry, ".json")
            uc_sol = read_json(joinpath(uc_path, entry))
            num_hours = length(uc_sol["Time"])
            for i in 1:num_hours
                hour_sum_gen_profit = 0
                for key in keys(uc_sol["Generator profits"])
                    hour_sum_gen_profit += uc_sol["Generator profits"][key][i]
                end
                hour_sum_gen_profit += uc_sol["Storage profits"]["BA"][i]
                append!(Gen_profit, hour_sum_gen_profit)
            end
            append!(Time, uc_sol["Time"])
            append!(Consumers_payment, uc_sol["Charge consumers"])
            append!(Total_cost, uc_sol["System operator cost"])
        end
    end
    df = DataFrame(Time = Time, Consumers_payment = Consumers_payment, Total_cost = Total_cost, Gen_profit = Gen_profit)
    return df
end


function one_file_cost_in_model(POLICY::String, res_dir::String, run_date::Dates.Date, file_date::Dates.Date, extract_len::Int64)
    path_dir = joinpath(res_dir, "Master_$(POLICY)")
    @assert isdir(path_dir) error("Directory not found for $(POLICY)")
    uc_file = joinpath(path_dir, "$(POLICY)_$(run_date)", "UC_$(file_date).json")

    Gen_profit = []
    uc_sol = read_json(uc_file)
    for i in 1:extract_len
        hour_sum_gen_profit = 0
        for key in keys(uc_sol["Generator Profits"])
            hour_sum_gen_profit += uc_sol["Generator Profits"][key][i]
        end
        for key in keys(uc_sol["Other Profits"])
            hour_sum_gen_profit += uc_sol["Other Profits"][key][i]
        end
        append!(Gen_profit, hour_sum_gen_profit)
    end

    df = DataFrame(Time = uc_sol["Time"][1:extract_len], Consumers_payment = uc_sol["Charge consumers"][1:extract_len], Total_cost = uc_sol["System operator cost"][1:extract_len], Gen_profit = Gen_profit)
    return df
end


# df_AVG = year_cost_in_model(model[2], uc_folder_dic)
# df_NLB = year_cost_in_model(model[3], uc_folder_dic)
# year_result = leftjoin(df_AVG, df_NLB, on = :Time, makeunique = true)
# new_columns = ["Time", "AVG_Consumers_payment", "AVG_Total_cost", "AVG_Gen_profit", "NLB_Consumers_payment", "NLB_Total_cost", "NLB_Gen_profit"]
# rename!(year_result, Symbol.(new_columns))
# CSV.write(joinpath(result_dir, "year_cost.csv"), year_result)

# filename = "UC_2019-01-01.json"
# uc_sol = read_json("/Users/hanshu/Desktop/Price_formation/Result/Master_STOCH/S-UCED_2024-05-21/UC_2019-01-01.json")
# extract_len = length(uc_sol["Time"])

run_dates = Dict("SB" => Dates.Date(2024,10,2), 
                "PF" => Dates.Date(2024,10,8),
                "MF" => Dates.Date(2024,10,4),
                "BNR" => Dates.Date(2024,10,4), 
                "WF" => Dates.Date(2024,10,5),
                "DR60" => Dates.Date(2024,10,16))

res_dir = "/Users/hanshu/Desktop/Price_formation/Result"
df = DataFrame()
uc_sol = read_json("/Users/hanshu/Desktop/Price_formation/Result/Master_SB/SB_2024-10-02/UC_2019-01-01.json")
extract_len = length(uc_sol["Time"])
for POLICY in collect(keys(run_dates))
    global df
    run_date = run_dates[POLICY]
    file_date = Dates.Date(2019,1,1)
    policy_cost = one_file_cost_in_model(POLICY, res_dir, run_date, file_date, extract_len)
    if isempty(df)
        df = policy_cost
    else
        df = leftjoin(df, policy_cost, on = :Time, makeunique = true)
    end
end

property = ["Consumers_payment", "Total_cost", "Gen_profit"]
new_columns = ["Time"]
for POLICY in collect(keys(run_dates))
    for prop in property
        append!(new_columns, [string(POLICY, "_", prop)])
    end
end
DataFrames.rename!(df, Symbol.(new_columns))

for POLICY in keys(run_dates)
    println("Policy: $(POLICY), Total cost: $(sum(df[!, string(POLICY, "_Total_cost")]))")  
end

# file_cost_STOCH = one_file_cost_in_model("STOCH", filename, extract_len, uc_folder_dic)
# file_cost_AVG = one_file_cost_in_model("AVG", filename, extract_len, uc_folder_dic)
# file_cost_NLB = one_file_cost_in_model("NLB", filename, extract_len, uc_folder_dic)
# file_result = leftjoin(file_cost_STOCH, file_cost_AVG, on = "Time", makeunique = true)
# file_result = leftjoin(file_result, file_cost_NLB, on = "Time", makeunique = true)
# new_columns = ["Time", "STOCH_Consumers_payment", "STOCH_Total_cost", "STOCH_Gen_profit", "AVG_Consumers_payment", "AVG_Total_cost", "AVG_Gen_profit", "NLB_Consumers_payment", "NLB_Total_cost", "NLB_Gen_profit"]
# rename!(file_result, Symbol.(new_columns))
# CSV.write(joinpath(result_dir, "21days_cost.csv"), file_result)