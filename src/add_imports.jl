function _add_imports!(sys::System, model::JuMP.Model)::Nothing
    expr_net_injection = model[:expr_net_injection]
    scenarios = model[:param].scenarios
    time_steps = model[:param].time_steps

    # Define imports supply curve 
    imports_price = [25, 40, 100]
    imports_MW = [1500, 1500, 200]
    # imports_price = [1000]
    # imports_MW = [3500]
    @assert length(imports_price) == length(imports_MW)
    imports_segments = 1:length(imports_price)

    @variable(model, imports[s in scenarios, t in time_steps, k in imports_segments], lower_bound = 0)
    for s in scenarios, t in time_steps, k in imports_segments
        @constraint(model, imports[s,t,k] <= imports_MW[k])
        add_to_expression!(expr_net_injection[s,t], imports[s,t,k], 1.0)
        add_to_expression!(model[:obj], imports[s,t,k], imports_price[k]/length(scenarios))
    end
    return
end