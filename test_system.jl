include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/add_quantile_ts.jl") # function to add quantile time series data
include("NYGrid/comp_new_reserve_req.jl")
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")
include("src/get_uc_op_price.jl")


@info "Build NY system"
sys = build_ny_system(base_power = 100)
thermal_gen_names = get_name.(get_components(ThermalGen, sys))
storage_names = get_name.(get_components(GenericBattery, sys))
pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)

total_pg_lim = sum(pg_lim[g].max for g in thermal_gen_names)
fast_pg_lim1 = 0
fast_pg_lim2 = 0
for g in thermal_gen_names
    global fast_pg_lim1, fast_pg_lim2
    time_limits = get_time_limits(get_component(ThermalGen, sys, g))
    if time_limits[:up] <= 1
        fast_pg_lim1 += pg_lim[g].max
    end
    if time_limits[:up] <= 2
        fast_pg_lim2 += pg_lim[g].max
    end
end