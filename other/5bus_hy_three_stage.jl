using PowerSystemCaseBuilder
using PowerSystems, PowerSimulations, HydroPowerSimulations
using HiGHS, Logging, Dates
const PSI = PowerSimulations

sys_hy_wk = build_system(PSISystems, "5_bus_hydro_wk_sys")
sys_hy_uc = build_system(PSISystems, "5_bus_hydro_uc_sys")
sys_hy_ed = build_system(PSISystems, "5_bus_hydro_ed_sys")

sys_hy_wk_targets = build_system(PSISystems, "5_bus_hydro_wk_sys_with_targets")
sys_hy_uc_targets = build_system(PSISystems, "5_bus_hydro_uc_sys_with_targets")
sys_hy_ed_targets = build_system(PSISystems, "5_bus_hydro_ed_sys_with_targets")

solver = optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.05)

# solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.5)
odir = mktempdir(cleanup=true)

template_md = ProblemTemplate()
set_device_model!(template_md, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_md, PowerLoad, StaticPowerLoad)
set_device_model!(template_md, HydroEnergyReservoir, HydroDispatchReservoirStorage)

# For the daily model, we can increase the modeling detail since we'll be solving shorter
# problems.
template_da = ProblemTemplate()
set_device_model!(template_da, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_da, PowerLoad, StaticPowerLoad)
set_device_model!(template_da, HydroEnergyReservoir, HydroDispatchReservoirStorage)

template_ed = ProblemTemplate()
set_device_model!(template_ed, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_ed, PowerLoad, StaticPowerLoad)
set_device_model!(template_ed, HydroEnergyReservoir, HydroDispatchReservoirStorage)

# # 3-Stage Simulation:
transform_single_time_series!(sys_hy_wk, 2, Hour(24))

problems = SimulationModels(
    decision_models=[
        DecisionModel(
            template_md,
            sys_hy_wk_targets,
            name="MD",
            optimizer=solver,
            system_to_file=false,
            initialize_model=false,
            calculate_conflict = true,
        ),
        DecisionModel(
            template_da,
            sys_hy_uc_targets,
            name="DA",
            optimizer=solver,
            system_to_file=false,
            initialize_model=false,
            calculate_conflict = true,
        ),
        DecisionModel(
            template_ed,
            sys_hy_ed_targets,
            name="ED",
            optimizer=solver,
            system_to_file=false,
            initialize_model=false,
            calculate_conflict = true,
        ),
    ],
)

sequence = SimulationSequence(
    models=problems,
    feedforwards=Dict(
        "DA" => [
            SemiContinuousFeedforward(
                component_type=HydroEnergyReservoir,
                source=ActivePowerVariable,
                affected_values=[ActivePowerVariable],
            ),
        ],
        "ED" => [
            SemiContinuousFeedforward(
                component_type=HydroEnergyReservoir,
                source=ActivePowerVariable,
                affected_values=[ActivePowerVariable],
            ),
        ],
    ),
    ini_cond_chronology=InterProblemChronology(),
);

sim = Simulation(
    name="hydro",
    steps=1,
    models=problems,
    sequence=sequence,
    simulation_folder=odir,
)

build!(sim)

execute!(sim, enable_progress_bar=false)

# uc_problem = DecisionModel(template_da, sys_hy_uc_targets, optimizer=solver, name="DA", horizon=24)
# build!(uc_problem, output_dir=odir)
# solve!(uc_problem)
PSI.get_optimizer_stats(sim.models.decision_models[1])
PSI.get_decision_problem_results(results, "DA")
jump_md = PSI.get_jump_model(sim.models.decision_models[1])
jump_da = PSI.get_jump_model(sim.models.decision_models[2])
# Error: Constraints participating in conflict basis (IIS) 
# │ 
# │ ┌──────────────────────────────────────────────────────────────────────────────────┐
# │ │ FeedforwardSemiContinousConstraint__HydroEnergyReservoir__ActivePowerVariable_ub │
# │ ├──────────────────────────────────────────────────────────────────────────────────┤
# │ │                                                            ("HydroDispatch1", 1)

# c = PSI.get_constraint(
#         PSI.get_optimization_container(ac_power_model),
#         FeedforwardSemiContinousConstraint(),
#         ThermalStandard,
#         "ActivePowerVariable_ub",
#     )
uc_power_model = PSI.get_simulation_model(PSI.get_models(sim), :DA)
c = PSI.get_constraint(
        PSI.get_optimization_container(uc_power_model),
        FeedforwardSemiContinousConstraint(),
        HydroEnergyReservoir,
        "ActivePowerVariable_ub",
    )

results = SimulationResults(sim, ignore_status = true);
md_results = get_decision_problem_results(results, "MD")
da_results = get_decision_problem_results(results, "DA")
ed_results = get_decision_problem_results(results, "ED");
list_dual_names(ed_results)
prices = read_dual(ed_results, "CopperPlateBalanceConstraint__System")
read_realized_dual(ed_results, "CopperPlateBalanceConstraint__System")


PSI.get_decision_problem_results(sim, "DA")