using JSON, DataStructures

function _init(model::JuMP.Model, key::Symbol)::OrderedDict
    if !(key in keys(object_dictionary(model)))
        model[key] = OrderedDict()
    end
    return model[key]
end

function write_json(filename::AbstractString, solution::OrderedDict)::Nothing
    open(filename, "w") do file 
        return JSON.print(file, solution, 2)
    end
    return 
end

function read_json(filename::AbstractString)::OrderedDict
    return JSON.parse(open(filename), dicttype = () -> DefaultDict(nothing))
end

function get_model_file_name(; theta::Union{Nothing, Int64} = nothing, scenario_count::Int64, result_dir::AbstractString)
    if !isnothing(theta)
        @assert scenario_count == 1 "Define theta for DLAC-NLB but scenario_count != 1"
        model_name = "DLAC-NLB-$(theta)"
    else
        scenario_count = scenario_count # set scenario count 1 for deterministic, 10 for stochastic
        model_name = scenario_count == 1 ? "DLAC-AVG" : "SLAC"
    end
    solution_file = joinpath(result_dir, "$(model_name)_sol_$(Dates.today()).json")
    return model_name, solution_file    
end

function get_UCED_model_folder_name(; theta::Union{Nothing, Int64} = nothing, scenario_count::Int64)
    if !isnothing(theta)
        @assert scenario_count == 1 "Define theta for DLAC-NLB but scenario_count != 1"
        model_name = "NLB-$(theta)-UCED"
        master_name = "NLB"
    else
        model_name = scenario_count == 1 ? "AVG-UCED" : "S-UCED"
        master_name = scenario_count == 1 ? "AVG" : "STOCH"
    end
    master_folder = "Master_$(master_name)"
    uc_folder = "$(model_name)_$(Dates.today())"
    ed_folder = "ED_$(model_name)_$(Dates.today())"
    return model_name, master_folder, uc_folder, ed_folder 
end

"""
Write the model to a text file
"""
function write_model_txt(model::JuMP.Model, model_name::AbstractString, result_dir::AbstractString)::Nothing
    model_str = string(model)
    open(joinpath(result_dir, "$(model_name).txt"), "w") do file
        write(file, model_str)
    end
    return
end

function find_sol_files(result_dir::AbstractString, master_folder::AbstractString, uc_folder::AbstractString, ed_folder::AbstractString)
    uc_time = Dates.Date(2019,12,1)
    while true
        uc_sol_file = joinpath(result_dir, master_folder, uc_folder, "UC_$(Date(uc_time)).json")
        ed_sol_file = joinpath(result_dir, master_folder, ed_folder, "ED_$(Date(uc_time)).json")
        if (isfile(uc_sol_file) && isfile(ed_sol_file))
            uc_sol = read_json(uc_sol_file)
            if length(uc_sol["Time"]) >= 24 # check if the solution is at least for 24 hours
                return uc_sol_file, ed_sol_file
            else
                uc_time -= Dates.Month(1)
            end
        else
            uc_time -= Dates.Month(1)
        end
        if uc_time < Dates.Date(2019,1,1)
            error("No solution files found")
        end
    end
    return uc_sol_file, ed_sol_file
end

function determine_init_flag(result_dir::AbstractString, master_folder::AbstractString, uc_folder::AbstractString, ed_folder::AbstractString)
    init_fr_ED_flag, init_fr_file_flag = true, false
    if ispath(joinpath(result_dir, master_folder, uc_folder)) && !isempty(readdir(joinpath(result_dir, master_folder, uc_folder)))
        try 
            find_sol_files(result_dir, master_folder, uc_folder, ed_folder)
        catch e
            return init_fr_ED_flag, init_fr_file_flag
        end
        init_fr_ED_flag, init_fr_file_flag = false, true
    end
    
    return init_fr_ED_flag, init_fr_file_flag 
end