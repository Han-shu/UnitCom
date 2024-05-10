function print_conflict(model::JuMP.Model; write_iis = false, iis_path = nothing)::Nothing
    println(
            """
            The model was not solved correctly:
            termination_status : $(termination_status(model))
            primal_status      : $(primal_status(model))
            dual_status        : $(dual_status(model))
            raw_status         : $(raw_status(model))
            """,
        )

    JuMP.compute_conflict!(model)

    if MOI.get(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
        iis_model, referece_map = copy_conflict(model)
        println(iis_model)
        if write_iis
            if isnothing(iis_path)
                write_to_file(iis_model, "iis_model.mps")
            else
                write_to_file(iis_model, joinpath(iis_path, "iis_model.mps"))
            end
        end
    elseif MOI.get(model, MOI.ConflictStatus()) == MOI.NO_CONFLICT_EXISTS
        @info "Model was proven to be unbounded."
        # optimizer = optimizer_with_attributes(Gurobi.Optimizer, "DualReduction" => 0)
        # set_optimizer(model, optimizer)
        # optimize!(model)
    else
        error("Unknown status")
    end
end
