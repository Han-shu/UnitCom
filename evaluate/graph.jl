using Plots, Dates, JuMP

include("../src/functions.jl")
function extract_LMP(model_name::AbstractString, run_date)::Tuple{Array{Float64}, Array{Float64}}
    uc_LMP, ed_LMP = [], []
    file_date = Dates.Date(2018,12,1)
    AVG_dir = "/Users/hanshu/Desktop/Price_formation/Result/Master_AVG"
    NLB_dir = "/Users/hanshu/Desktop/Price_formation/Result/Master_NLB"
    STOCH_dir = "/Users/hanshu/Desktop/Price_formation/Result/Master_STOCH"
    if model_name == "AVG-UCED"
        path_dir = AVG_dir
    elseif model_name == "NLB-10-UCED"
        path_dir = NLB_dir
    elseif model_name == "S-UCED"
        path_dir = STOCH_dir
    else
        error("File path not defined for $(model_name)")
    end

    while true
        file_date += Dates.Month(1)
        uc_file = joinpath(path_dir, "$(model_name)_$(run_date)", "UC_$(file_date).json")
        ed_file = joinpath(path_dir, "ED_$(model_name)_$(run_date)", "ED_$(file_date).json")
        if !isfile(uc_file) || !isfile(ed_file)
            break
        end
        @info "Extracting LMP for $(model_name) with date $(file_date)"
        uc_solution = read_json(uc_file)
        ed_solution = read_json(ed_file)
        append!(uc_LMP, uc_solution["Hourly average LMP"])
        for i in ed_solution["LMP"]
            append!(ed_LMP, i)
        end
    end
    return uc_LMP, ed_LMP
end

function plot_hour_min_LMP(uc_LMP::Array{Float64}, ed_LMP::Array{Float64}, model_name::AbstractString)
    hour_x= range(1, length(uc_LMP), step = 1)
    min5_x= range(1/12, length(uc_LMP), step = 1/12)
    p = plot(hour_x, uc_LMP, label = "$(model_name)", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
    plot!(min5_x, ed_LMP, label = "ED_$(model_name)")
    return p
end

function plot_hour_LMP(LMP::Vector{Vector{Float64}}, model_name::Vector{String})
    x_end = minimum([length(LMP[i]) for i in 1:length(LMP)])
    hour_x= range(1, x_end, step = 1)
    p = plot(hour_x, LMP[1], label = "$(model_name[1])", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)
    for i in 2:length(LMP)
        plot!(hour_x, LMP[i], label = "$(model_name[i])")
    end
    return p
end

uc_AVG_LMP, ed_AVG_LMP = extract_LMP("AVG-UCED", Dates.Date(2024,5,15))
uc_NLB_LMP, ed_NLB_LMP = extract_LMP("NLB-10-UCED", Dates.Date(2024,5,14))
uc_STOCH_LMP, ed_STOCH_LMP = extract_LMP("S-UCED", Dates.Date(2024,5,21))


p1 = plot_hour_min_LMP(uc_AVG_LMP, ed_AVG_LMP, "AVG-UCED")
p2 = plot_hour_min_LMP(uc_NLB_LMP, ed_NLB_LMP, "NLB-10-UCED")
p_stoch = plot_hour_min_LMP(uc_STOCH_LMP, ed_STOCH_LMP, "S-UCED")
p_Hour = plot_hour_LMP([uc_AVG_LMP, uc_NLB_LMP, uc_STOCH_LMP], ["AVG-UCED", "NLB-10-UCED", "S-UCED"])

p_Hour = plot_hour_LMP([uc_STOCH_LMP], ["S-UCED"])

# LMP = [uc_AVG_LMP, uc_NLB_LMP, uc_STOCH_LMP]
# minimum([length(LMP[i]) for i in 1:length(LMP)])