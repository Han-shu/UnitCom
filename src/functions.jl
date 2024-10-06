using JuMP, JSON, DataStructures

function _read_h5_by_idx(file::String, time::Dates.DateTime)
    return h5open(file, "r") do file
        return read(file, string(time))
    end
end

function _extract_fcst_matrix(file::String, time::Dates.DateTime, min5_flag::Bool)
    matrix = _read_h5_by_idx(file, time)
    # the first scenario is the historical data, so we skip it
    if min5_flag
        # ED: Use from 1st time point
        return matrix[:, 1], matrix[:, 2:end]
    else
        # UC: Use from 2nd time point becase the first time point is the historical data
        return matrix[2:end, 1], matrix[2:end, 2:end]
    end
end

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

function policy_model_folder_name(policy::String, date::Date = Dates.today())
    master_folder = "Master_$(policy)"
    uc_folder = "$(policy)_$(date)"
    ed_folder = "ED_$(policy)_$(date)"
    return master_folder, uc_folder, ed_folder
end

function policy_theta_parameter(POLICY::String)
    if POLICY == "SB"
        theta = nothing
        scenario_cnt = 11
    elseif POLICY == "MLF"
        theta = 1
        scenario_cnt = 1
    elseif POLICY == "BNR"
        theta = 11
        scenario_cnt = 1
    elseif POLICY == "WF"
        theta = 100
        scenario_cnt = 1
    elseif POLICY in ["NR", "FR", "DR"]
        theta = nothing
        scenario_cnt = 1
    else
        error("Policy $POLICY is not defined")
    end
    return theta, scenario_cnt
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