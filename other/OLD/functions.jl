function get_model_file_name(; theta::Union{Nothing, Int64} = nothing, scenario_cnt::Int64, result_dir::AbstractString, date::Date = Dates.today())
    if !isnothing(theta)
        @assert scenario_cnt == 1 "Define theta for DLAC-NLB but scenario_cnt != 1"
        model_name = "DLAC-NLB-$(theta)"
    else
        scenario_count = scenario_cnt # set scenario count 1 for deterministic, 10 for stochastic
        model_name = scenario_cnt == 1 ? "DLAC-AVG" : "SLAC"
    end
    solution_file = joinpath(result_dir, "$(model_name)_sol_$(date).json")
    return model_name, solution_file    
end

function get_UCED_model_folder_name(; theta::Union{Nothing, Int64} = nothing, scenario_cnt::Int64, date::Date = Dates.today())
    if !isnothing(theta)
        @assert scenario_cnt == 1 "Define theta for DLAC-NLB but scenario_cnt != 1"
        model_name = "NLB-$(theta)"
        master_name = "NLB"
    else
        model_name = scenario_cnt == 1 ? "AVG" : "STOCH"
        master_name = scenario_cnt == 1 ? "AVG" : "STOCH"
    end
    master_folder = "Master_$(master_name)"
    uc_folder = "$(model_name)_$(date)"
    ed_folder = "ED_$(model_name)_$(date)"
    return model_name, master_folder, uc_folder, ed_folder 
end