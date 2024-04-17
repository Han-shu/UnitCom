using JSON

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