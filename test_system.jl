include("NYGrid/build_ny_system.jl") # function to build the NYGrid system
include("NYGrid/add_scenarios_ts.jl") # function to add scenario time series data
include("NYGrid/comp_new_reserve_req.jl")
include("src/stochastic_uc.jl")
include("src/stochastic_ed.jl")
include("src/get_solution.jl")
include("src/functions.jl")
include("src/get_init_value.jl")
include("src/get_uc_op_price.jl")


@info "Build NY system"
sys = build_ny_system(base_power = 100)

# Thermal generators
thermal_gen_names = get_name.(get_components(ThermalGen, sys))
pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
get_rmp_up_limit(g) = PSY.get_ramp_limits(g).up
get_rmp_dn_limit(g) = PSY.get_ramp_limits(g).down
ramp_10 = Dict(g => get_rmp_up_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
ramp_30 = Dict(g => get_rmp_dn_limit(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
fixed_cost = Dict(g => get_fixed(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
startup_cost = Dict(g => get_start_up(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
shutdown_cost = Dict(g => get_shut_down(get_operation_cost(get_component(ThermalGen, sys, g))) for g in thermal_gen_names)
variable_cost = Dict(g => get_cost(get_variable(get_operation_cost(get_component(ThermalGen, sys, g)))) for g in thermal_gen_names)
time_limits = Dict(g => get_time_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)

# Storage
storage_names = PSY.get_name.(get_components(PSY.GenericBattery, sys))
eb_lim = Dict(b => get_state_of_charge_limits(get_component(GenericBattery, sys, b)) for b in storage_names)
η = Dict(b => get_efficiency(get_component(GenericBattery, sys, b)) for b in storage_names)
kb_charge_max = Dict(b => get_input_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)
kb_discharge_max = Dict(b => get_output_active_power_limits(get_component(GenericBattery, sys, b))[:max] for b in storage_names)


res_dir = "/Users/hanshu/Desktop/Price_formation/Result"
nocommit_g = ["Holtsville 04", "Barrett ST 02", "Holtsville 03", "Batavia", "Astoria GT 01", "Glenwood GT 02", "West Babylon 4", "Holtsville 06", "Oswego 6", "Nassau Energy Corporation", "General Mills Inc", "Rensselaer", "Carr St.-E. Syr", "Freeport 2-3", "Bethpage", "Wading River 1", "Ravenswood ST 03", "Hillburn GT", "Holtsville 05", "Barrett 08", "Danskammer 1", "Lockport", "Port Jefferson 4", "Ravenswood ST 01", "Flynn", "Barrett 10", "Ravenswood 01", "Glenwood GT 03", "Barrett 03", "Wading River 3", "East Hampton 2", "Holtsville 10", "Hudson Ave 3", "Oswego 5", "Barrett 11", "Kent", "Sterling", "Bethpage 3", "74 St.  GT 1", "Hudson Ave 4", "Hudson Ave 5", "South Cairo", "Northport 2", "Barrett GT 02", "Barrett 06", "Holtsville 02", "Roseton 1", "Barrett GT 01", "KIAC_JFK_GT2", "Pinelawn Power 1", "Holtsville 01", "Barrett 04", "Holtsville 09", "Coxsackie GT", "Barrett 05", "Brooklyn Navy Yard", "Arthur Kill GT 1", "Barrett ST 01", "Wading River 2", "Roseton 2", "Ravenswood ST 02", "Danskammer 2", "74 St.  GT 2", "Northport 4", "59 St.  GT 1", "Fortistar - N.Tonawanda", "East Hampton 3", "Port Jefferson 3", "Astoria 3", "Freeport CT 1", "East Hampton 4"]   
output_file = "Gen_commit.csv"
df = DataFrame(Gen = [], ramp10 = [], ramp30 = [], pg_min = [], pg_max = [], fixed_cost = [], startup_cost = [], variable_cost = [], minup = [], mindown = [], time_limits = [], commitment = [])
for g in thermal_gen_names
    if g in nocommit_g
        commit_status = false
    else
        commit_status = true
    end
    push!(df, [g, ramp_10[g], ramp_30[g], pg_lim[g].min, pg_lim[g].max, fixed_cost[g], startup_cost[g], variable_cost[g], time_limits[g].up, time_limits[g].down, time_limits[g].down, commit_status])
end
# CSV.write(joinpath(res_dir, output_file), df)
# println("Output written to ", joinpath(res_dir, output_file))



# start_time = DateTime(2019,1,1,0)
# scenario_count = 10
# horizon = 24
# VOLL=5000
# parameters = _construct_model_parameters(horizon, scenario_count, start_time, VOLL)
# parameters.reserve_requirements

# total_thermal_cap = sum(pg_lim[g].max for g in thermal_gen_names)
# println("Total thermal capacity: ", total_thermal_cap)