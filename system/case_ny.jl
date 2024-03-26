using PowerSystems, PowerSimulations, HydroPowerSimulations
using PowerSystemCaseBuilder

# Define the system
sys = System(joinpath("/Users/hanshu/Desktop/Price_formation/Data/NYGrid", "case_ny.m"))

matlab_sys = build_system(MatpowerTestSystems, "matpower_RTS_GMLC_sys")

sys_5bus = System("/Users/hanshu/Desktop/Price_formation/Data/NYGrid/case5_re.m")

"/Users/hanshu/Desktop/Price_formation/Data/NYGrid/case_ny.m"

file_dir = joinpath(pkgdir(PowerSystems), "docs", "src", "tutorials", "tutorials_data")
system = System(joinpath(file_dir, "RTS_GMLC.m"));

sys5 = System(joinpath(file_dir, "case5.m"));

"/Users/hanshu/Desktop/Price_formation/Data/NYGrid/case_ny.m"


