using PowerSystems, PowerSimulations, HydroPowerSimulations
using Dates, Gurobi

file_path = "/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/"
initial_time = "2018-03-15T00:00:00"
solver = optimizer_with_attributes(Gurobi.Optimizer, "mip_rel_gap" => 0.05)

# solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.5)

############################## Stage 1 Problem Definition, UC ##############################
sys_da = System(file_path*"DA_sys_31_scenarios.json")
template_dauc = ProblemTemplate()
set_device_model!(template_dauc, ThermalMultiStart, ThermalMultiStartUnitCommitment)
set_device_model!(template_dauc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_dauc, PowerLoad, StaticPowerLoad)
set_device_model!(template_dauc, HydroDispatch, FixedOutput)
set_service_model!(template_dauc, VariableReserve{ReserveUp}, RangeReserve)
set_service_model!(template_dauc, VariableReserve{ReserveDown}, RangeReserve)

UC = DecisionModel(template_dauc, sys_da, optimizer = solver, name = "UC", initial_time = DateTime(initial_time))

build!(UC, output_dir = mktempdir())
solve!(UC)
#################################### Stage 2 Problem Definition, ED ########################

sys_ha = System(file_path * "HA_sys_UC_experiment.json")
template_hauc = ProblemTemplate()
### Using Dispatch here, not the same as above
set_device_model!(template_hauc, ThermalMultiStart, ThermalCompactDispatch)
set_device_model!(template_hauc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_hauc, PowerLoad, StaticPowerLoad)
set_device_model!(template_hauc, HydroDispatch, FixedOutput)
set_service_model!(template_hauc, VariableReserve{ReserveUp}, RangeReserve)
set_service_model!(template_hauc, VariableReserve{ReserveDown}, RangeReserve)

HAUC = DecisionModel(template_hauc, sys_ha, optimizer = solver, name = "HAUC", initial_time = DateTime(initial_time), calculate_conflict = true)

build!(HAUC, output_dir = mktempdir())
solve!(HAUC)

#################################### Simulation Definition ################################
models = SimulationModels(
    decision_models = [UC, HAUC],
)

feedforward = Dict(
    "HAUC" => [
        SemiContinuousFeedforward(
            component_type = ThermalMultiStart,
            source = OnVariable,
            affected_values = [ActivePowerVariable],
        ),
    ],
)

DA_RT_sequence = SimulationSequence(
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

sim = Simulation(
    name = "doubleday",
    steps = 2,
    models = models,
    sequence = DA_RT_sequence,
    simulation_folder = mktempdir(".", cleanup = true),
)

build!(sim)

execute!(sim, enable_progress_bar = false)

results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC"); # UC stage result metadata
ed_results = get_decision_problem_results(results, "HAUC"); # ED stage result metadata


renewables = collect(get_components(RenewableGen, sys_da))
get_time_series_array(Deterministic, renewables[2], "max_active_power")

area = get_component(Area, sys_da, "FarWest")
get_time_series_values(Scenarios, area, "solar_power")
get_time_series_array(Scenarios, area, "solar_power")
get_time_series_array(Deterministic, area, "max_active_power")