function print_conflict(model::JuMP.Model; write_iis = false, iis_path = nothing)::Nothing
    @error "Optimizer returned status: $model_status"
    JuMP.compute_conflict!(model)
    optimize!(model)

    if MOI.get(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
        iis_model, _ = copy_conflict(model)
        println(iis_model)
        if write_iis
            if isnothing(iis_path)
                write_to_file(iis_model, "iis_model.mps")
            else
                write_to_file(iis_model, joinpath(iis_path, "iis_model.mps"))
            end
        end
    end
end