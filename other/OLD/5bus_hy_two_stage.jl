using Gurobi, JuMP, Ipopt
using PowerSystems, PowerSimulations, PowerSystemCaseBuilder
const PSI = PowerSimulations
const PSY = PowerSystems

template_uc = ProblemTemplate(CopperPlatePowerModel)
set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, StaticLoad, StaticPowerLoad)
set_device_model!(template_uc, InterruptiblePowerLoad, StaticPowerLoad)
set_device_model!(template_uc, HydroEnergyReservoir, HydroDispatchRunOfRiver)
set_network_model!(template_uc, NetworkModel(DCPPowerModel; use_slacks = true))
# network slacks added because of data issues
template_ed = ProblemTemplate(NetworkModel(ACPPowerModel; use_slacks = true))
set_device_model!(template_ed, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_ed, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_ed, StaticLoad, StaticPowerLoad)
set_device_model!(template_ed, InterruptiblePowerLoad, PowerLoadDispatch)
set_device_model!(template_ed, HydroEnergyReservoir, HydroDispatchRunOfRiver)

c_sys5_hy_uc = build_system(PSITestSystems, "c_sys5_hy_uc")
c_sys5_hy_ed = build_system(PSITestSystems, "c_sys5_hy_ed")

Gurobi_optimizer = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer,
    "time_limit" => 100.0,
    "log_to_console" => false,
)

ipopt_optimizer =
    JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0)
fast_ipopt_optimizer = JuMP.optimizer_with_attributes(
    Ipopt.Optimizer,
    "print_level" => 0,
    "max_cpu_time" => 5.0,
)

models = SimulationModels(;
    decision_models = [
        DecisionModel(
            template_uc,
            c_sys5_hy_uc;
            name = "UC",
            optimizer = Gurobi_optimizer,
            initialize_model = false,
            calculate_conflict = true,
        ),
        DecisionModel(
            template_ed,
            c_sys5_hy_ed;
            name = "ED",
            optimizer = ipopt_optimizer,
            initialize_model = false,
            calculate_conflict = true,
        ),
    ],
)

sequence = SimulationSequence(;
    models = models,
    feedforwards = Dict(
        "ED" => [
            SemiContinuousFeedforward(;
                component_type = ThermalStandard,
                source = OnVariable,
                affected_values = [ActivePowerVariable, ReactivePowerVariable],
            ),
        ],
    ),
    ini_cond_chronology = InterProblemChronology(),
)

sim = Simulation(;
    name = "reactive_feedforward",
    steps = 2,
    models = models,
    sequence = sequence,
    simulation_folder = mktempdir(; cleanup = true),
)
build_out = build!(sim)

execute!(sim, enable_progress_bar=false)