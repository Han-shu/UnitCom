using Dates, DataFrames, CSV
file_dir = "/Users/hanshu/Desktop/Price_formation/Data/NYGrid/FuelMix"

# Read CSV files and extract hydro generation data
hydro_ts = DataFrame()
for run_time in DateTime(2018, 12, 31):Day(1):DateTime(2019, 12, 31)
    global hydro_ts
    year = Dates.year(run_time)
    month = Dates.month(run_time)
    day = Dates.day(run_time)
    day = length(string(day)) == 1 ? "0"*string(day) : string(day)
    month = length(string(month)) == 1 ? "0"*string(month) : string(month)
    file = joinpath(file_dir, "$(year)$(month)01rtfuelmix_csv/$(year)$(month)$(day)rtfuelmix.csv")
    df = CSV.read(file, DataFrame)
    df_hydro = df[df[!, "Fuel Category"] .== "Hydro", :]
    hydro_ts = vcat(hydro_ts, df_hydro)
end
# Convert the time stamp to DateTime
hydro_ts[!, "Time Stamp"] = Dates.DateTime.(hydro_ts[!, "Time Stamp"], "mm/dd/yyyy HH:MM:SS")

# Correct the time zone EDT to EST
for idx in 1:size(hydro_ts,1)
    if hydro_ts[idx, "Time Zone"] == "EDT"
        dt = hydro_ts[idx, "Time Stamp"] 
        hydro_ts[idx, "Time Stamp"] = dt - Hour(1)
        hydro_ts[idx, "Time Zone"] = "EST"
    end 
end

function _complete_hydro_df(df::DataFrame)::DataFrame
    new_df = DataFrame()
    for idx in 1:size(df,1)-1
        dt1 = df[idx, "Time Stamp"]
        dt2 = df[idx+1, "Time Stamp"]
        if minute(dt1)%5 !=0 || second(dt1) != 0  
            continue
        else
            push!(new_df, df[idx, :])
            if dt2 - dt1 != Minute(5)
                gap_steps = (dt2 - dt1)/Minute(5) - 1
                gen1 = df[idx, "Gen MW"]
                gen2 = df[idx+1, "Gen MW"]
                for i in 1:gap_steps
                    new_dt = dt1 + Minute(5)*i
                    new_row = [new_dt, "EST", "Hydro", gen1 + (gen2 - gen1)/(gap_steps+1)*i]
                    push!(new_df, new_row)
                end
            end
        end
    end 
    push!(new_df, df[end, :])
    return new_df
end

hydro_ts2 = _complete_hydro_df(hydro_ts)
min5_hydro_ts = _complete_hydro_df(hydro_ts2)
@assert size(min5_hydro_ts, 1) == length(DateTime(2018, 12, 31, 0, 5):Minute(5):DateTime(2020, 1, 1)-Minute(5))
#Rename the columns
rename!(min5_hydro_ts, Dict("Time Stamp" => :Time_Stamp, "Time Zone" => :Time_Zone, "Fuel Category" => :Fuel_Category, "Gen MW" => :Gen_MW))
CSV.write("/Users/hanshu/Desktop/Price_formation/Data/NYGrid/hydro_2019.csv", min5_hydro_ts)