function print_conflict(model::JuMP.Model; write_iis = false)::Nothing
    @error "Optimizer returned status: $model_status"
    JuMP.compute_conflict!(model)
    optimize!(model)

    if MOI.get(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
        iis_model, _ = copy_conflict(model)
        println(iis_model)
        if write_iis
            write_to_file(iis_model, "iis_model.mps")
        end
    end
end