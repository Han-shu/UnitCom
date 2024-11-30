function _add_imports!(sys::System, model::JuMP.Model)::Nothing
    expr_net_injection = model[:expr_net_injection]
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps

    # Define imports supply curve 
    imports_segments = 1:2
    imports_value = [20, 30]

    @variable(model, imports[s in scenarios, t in time_steps, k in imports_segments], lower_bound = 0)
    for s in scenarios, t in time_steps, k in imports_segments
        @constraint(model, imports[s,t,k] <= 3000/length(imports_segments))
        add_to_expression!(expr_net_injection[s,t], imports[s,t,k], 1.0)
        add_to_expression!(model[:obj], imports[s,t,k], imports_value[k]/length(scenarios))
    end
    return
end