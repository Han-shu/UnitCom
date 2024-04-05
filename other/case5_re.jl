using PowerSystems
using JSON3, Dates, HDF5, Statistics
const PSY = PowerSystems


file_dir = joinpath(pkgdir(PowerSystems), "docs", "src", "tutorials", "tutorials_data")
system = System(joinpath(file_dir, "case5_re.m"), assign_new_uuids = true)
include("../NYGrid/parsing_utils.jl")