# Tutorial example from PowerSimulations.jl
using PowerSystems
using PowerSimulations
using HydroPowerSimulations
using PowerSystemCaseBuilder
using Gurobi # solver
using JuMP
# data
sys = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
# load an empty template
template_uc = ProblemTemplate()
# Add branch
set_device_model!(template_uc, Line, StaticBranch)
set_device_model!(template_uc, Transformer2W, StaticBranch)
set_device_model!(template_uc, TapTransformer, StaticBranch)
# Add injecrtion devices
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template_uc, RenewableFix, FixedOutput)

# Add reserve
set_service_model!(template_uc, VariableReserve{ReserveUp}, RangeReserve)
set_service_model!(template_uc, VariableReserve{ReserveDown}, RangeReserve)
# network
set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel))
# solver
solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.5)
# solver = optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.5)

# Build an DecisionModel
problem = DecisionModel(template_uc, sys; optimizer = solver, horizon = 24)
build!(problem, output_dir = mktempdir())

# Solve an DecisionModel
solve!(problem)
# Results inspection
res = ProblemResults(problem)
get_optimizer_stats(res)
read_variables(res)
list_parameter_names(res)
read_parameter(res, "ActivePowerTimeSeriesParameter__RenewableDispatch")