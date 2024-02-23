using PowerSystems, Gurobi, JuMP
using PowerSystemCaseBuilder

sys = System("/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/DA_sys_31_scenarios.json")

get_components(ThermalMultiStart, sys)
get_components(RenewableDispatch, sys)
thermal_gen_names = get_name.(get_components(ThermalGen, sys))
renewable_gen_names = get_name.(get_components(RenewableGen, sys))
uc_sys = System("/Users/hanshu/Desktop/Price_formation/Data/Doubleday_data/HA_sys_UC_experiment.json")


