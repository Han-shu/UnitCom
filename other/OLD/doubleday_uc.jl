using PowerSystems, Gurobi, JuMP
using PowerSimulations, PowerSystemCaseBuilder
using HydroPowerSimulations
using Dates
using TimeSeries
const PSI = PowerSimulations

path = "/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/"
sys = System(path*"DA_sys_31_scenarios.json")
# uc = template_unit_commitment()
uc = ProblemTemplate()

set_device_model!(uc, ThermalMultiStart, ThermalMultiStartUnitCommitment)
set_device_model!(uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(uc, StaticLoad, StaticPowerLoad)
# Use FixedOutput instead of HydroDispatchRunOfRiver to get consistent results because model might decide to curtail wind vs. hydro (same cost)
set_device_model!(uc, HydroDispatch, HydroDispatchRunOfRiver)


set_service_model!(uc, VariableReserve{ReserveUp}, RangeReserve)
set_service_model!(uc, VariableReserve{ReserveDown}, RangeReserve)


solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.5)
problem = DecisionModel(uc, sys, optimizer = solver, name = "UC", horizon = 36, initial_time = DateTime("2018-07-22T00:00:00"))

build!(problem, output_dir = mktempdir())
solve!(problem)

res = ProblemResults(problem)

