function write_json(filename::AbstractString, solution::OrderedDict)::Nothing
    open(filename, "w") do file 
        return JSON.print(file, solution, 2)
    end
    return 
end