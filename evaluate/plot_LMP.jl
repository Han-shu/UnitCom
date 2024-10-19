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

function plot_one_policy_hour_min_LMP(uc_LMPS::Dict{String, Vector{Float64}}, ed_LMPS::Dict{String, Vector{Float64}}, POLICY::AbstractString; min5_flag::Bool = false)
    hour_x= 1:length(uc_LMPS[POLICY])
    min5_x= range(1/12, step = 1/12, length = length(ed_LMPS[POLICY]))
    p = plot(hour_x, uc_LMPS[POLICY], label = "$(POLICY)", xlabel = "Hour", ylabel = "Price (\$/MWh)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
    if min5_flag
        plot!(min5_x, ed_LMPS[POLICY], label = "ED_$(POLICY)")
    end
    return p
end

function plot_mult_policies_hour_LMP(LMPS::Dict{String, Vector{Float64}})
    x_end = minimum(length(item) for item in values(LMPS))
    hour_x = 1:x_end
    p = nothing
    for (i,key) in enumerate(keys(LMPS))
        if i == 1
            p = plot(hour_x, LMPS[key][1:x_end], label = "$(key)", xlabel = "Hour", ylabel = "Price (\$/MWh)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11, ylims = (0, 100))
        else
            plot!(p, hour_x, LMPS[key][1:x_end], label = "$(key)")
        end
    end
    return p
end

res_dir = "/Users/hanshu/Desktop/Price_formation/Result"

run_dates = Dict("SB" => Dates.Date(2024,10,2), 
                "PF" => Dates.Date(2024,10,8),
                # "NR" => Dates.Date(2024,10,4),
                # "BNR" => Dates.Date(2024,10,4), 
                "WF" => Dates.Date(2024,10,5),
                "DR" => Dates.Date(2024,10,18))

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
    println("Policy: $(key), Average LMP: $(mean(hour_LMPS[key])), std: $(std(hour_LMPS[key]))")
end

p = plot_mult_policies_hour_LMP(hour_LMPS)

p = plot_one_policy_hour_min_LMP(hour_LMPS, min5_LMPS, "WF", min5_flag = false)

x_end = minimum(length(item) for item in values(hour_LMPS))
hour_x = 1:x_end
key = "WF"
p = plot(hour_x, hour_LMPS[key][1:x_end], label = "$(key)", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11, ylims = (0, 100))
key = "SB"
plot!(p, hour_x, hour_LMPS[key][1:x_end], label = "$(key)")


run_dates = Dict("DR" => [Dates.Date(2024,10,9), Dates.Date(2024,10,18)])
hour_LMPS = Dict{String, Vector{Float64}}()
min5_LMPS = Dict{String, Vector{Float64}}()
POLICY = "DR"
for rundate in run_dates[POLICY]
    uc_LMP, ed_LMP = extract_LMP(res_dir, POLICY, rundate)
    hour_LMPS[POLICY*"$(rundate)"] = uc_LMP
end
for key in keys(hour_LMPS)
    println("Policy: $(key), Average LMP: $(mean(hour_LMPS[key]))")
end
p = plot_mult_policies_hour_LMP(hour_LMPS)