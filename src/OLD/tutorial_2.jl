# Tutorial example from PowerSimulations.jl
# Sequential simulations
using PowerSystems
using PowerSimulations
using HydroPowerSimulations
const PSI = PowerSimulations
using PowerSystemCaseBuilder
using Dates
using Gurobi #solver

# solver
solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.5)
# solver = optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.5)

# hourly DA system
sys_DA = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
# 5-min RT system                                                                                                                            
sys_RT = build_system(PSISystems, "modified_RTS_GMLC_RT_sys")

# DA UC stage template
template_uc = template_unit_commitment()
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)

# Define the reference model for the real-time economic dispatch
template_ed = template_economic_dispatch(
    network = NetworkModel(PTDFPowerModel, use_slacks = true),
)
# Define the SimulationModels
models = SimulationModels(
    decision_models = [
        DecisionModel(template_uc, sys_DA, optimizer = solver, name = "UC"),
        DecisionModel(template_ed, sys_RT, optimizer = solver, name = "ED"),
    ],
)

# FeedForward
feedforward = Dict(
    "ED" => [
        SemiContinuousFeedforward(
            component_type = ThermalStandard,
            source = OnVariable,
            affected_values = [ActivePowerVariable],
        ),
    ],
)

# Sequencing
DA_RT_sequence = SimulationSequence(
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

sim = Simulation(
    name = "rts-test",
    steps = 2,
    models = models,
    sequence = DA_RT_sequence,
    simulation_folder = mktempdir(".", cleanup = true),
)

build!(sim)

execute!(sim, enable_progress_bar = false)

results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC"); # UC stage result metadata
ed_results = get_decision_problem_results(results, "ED"); # ED stage result metadata

read_variables(uc_results)
read_parameters(uc_results)
list_variable_names(uc_results)
list_parameter_names(uc_results)


