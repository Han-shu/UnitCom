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


function one_file_cost_in_model(model_name::String, filename, extract_len::Int64, uc_folder_dic::Dict{String, String})
    master_folder = "Master_"*model_name
    uc_folder = uc_folder_dic[model_name]
    uc_path = joinpath(result_dir, master_folder, uc_folder)
    file = joinpath(uc_path, filename)
    @assert isfile(file)

    Gen_profit = []
    uc_sol = read_json(file)
    for i in 1:extract_len
        hour_sum_gen_profit = 0
        for key in keys(uc_sol["Generator profits"])
            hour_sum_gen_profit += uc_sol["Generator profits"][key][i]
        end
        hour_sum_gen_profit += uc_sol["Storage profits"]["BA"][i]
        append!(Gen_profit, hour_sum_gen_profit)
    end

    df = DataFrame(Time = uc_sol["Time"][1:extract_len], Consumers_payment = uc_sol["Charge consumers"][1:extract_len], Total_cost = uc_sol["System operator cost"][1:extract_len], Gen_profit = Gen_profit)
    return df
end


df_AVG = year_cost_in_model(model[2], uc_folder_dic)
df_NLB = year_cost_in_model(model[3], uc_folder_dic)
year_result = leftjoin(df_AVG, df_NLB, on = :Time, makeunique = true)
new_columns = ["Time", "AVG_Consumers_payment", "AVG_Total_cost", "AVG_Gen_profit", "NLB_Consumers_payment", "NLB_Total_cost", "NLB_Gen_profit"]
rename!(year_result, Symbol.(new_columns))
CSV.write(joinpath(result_dir, "year_cost.csv"), year_result)

filename = "UC_2019-01-01.json"
uc_sol = read_json("/Users/hanshu/Desktop/Price_formation/Result/Master_STOCH/S-UCED_2024-05-21/UC_2019-01-01.json")
extract_len = length(uc_sol["Time"])
file_cost_STOCH = one_file_cost_in_model("STOCH", filename, extract_len, uc_folder_dic)
file_cost_AVG = one_file_cost_in_model("AVG", filename, extract_len, uc_folder_dic)
file_cost_NLB = one_file_cost_in_model("NLB", filename, extract_len, uc_folder_dic)
file_result = leftjoin(file_cost_STOCH, file_cost_AVG, on = "Time", makeunique = true)
file_result = leftjoin(file_result, file_cost_NLB, on = "Time", makeunique = true)
new_columns = ["Time", "STOCH_Consumers_payment", "STOCH_Total_cost", "STOCH_Gen_profit", "AVG_Consumers_payment", "AVG_Total_cost", "AVG_Gen_profit", "NLB_Consumers_payment", "NLB_Total_cost", "NLB_Gen_profit"]
rename!(file_result, Symbol.(new_columns))
CSV.write(joinpath(result_dir, "21days_cost.csv"), file_result)