using Plots, Dates, JuMP

include("../src/functions.jl")
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


res_dir = "/Users/hanshu/Desktop/Price_formation/Result"
run_dates = Dict("SB" => Dates.Date(2024,10,2), 
                "NR" => Dates.Date(2024,10,4), 
                "BNR" => Dates.Date(2024,10,4), 
                "WF" => Dates.Date(2024,10,5), 
                "SB" => Dates.Date(2024,10,2))
policies = collect(keys(run_dates))
hour_LMPS = Dict{String, Vector{Float64}}()
min5_LMPS = Dict{String, Vector{Float64}}()
for POLICY in policies
    uc_LMP, ed_LMP = extract_LMP(res_dir, POLICY, run_dates[POLICY])
    hour_LMPS[POLICY] = uc_LMP
    min5_LMPS[POLICY] = ed_LMP
end

using Statistics
for key in keys(hour_LMPS)
    println("Policy: $(key), Average LMP: $(mean(hour_LMPS[key]))")
end

POLICY = "WF"
run_date = run_dates[POLICY]    
file_date = Dates.Date(2019,1,1)
path_dir = joinpath(res_dir, "Master_$(POLICY)")
@assert isdir(path_dir) error("Directory not found for $(POLICY)")
uc_file = joinpath(path_dir, "$(POLICY)_$(run_date)", "UC_$(file_date).json")
ed_file = joinpath(path_dir, "ED_$(POLICY)_$(run_date)", "ED_$(file_date).json")
@info "Extracting LMP for $(POLICY) with date $(file_date)"
uc_solution = read_json(uc_file)
ed_solution = read_json(ed_file)

for t in 1:length(ed_solution["Time"])
    if mean(ed_solution["LMP"][t]) > 60
        println("Time: $(ed_solution["Time"][t]), LMP: $(ed_solution["LMP"][t])")
    end
end