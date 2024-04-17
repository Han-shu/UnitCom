using Plots
DLAC_solution = read_json(joinpath(result_dir, "DLAC_sol_2024-04-17.json"))
SLAC_solution = read_json(joinpath(result_dir, "SLAC_sol_2024-04-17.json"))
DLAC_45_solution = read_json(joinpath(result_dir, "DLAC-NLB-45_sol_2024-04-17.json"))
LMP = solution["LMP"]
x_end = length(SLAC_solution["LMP"])
x = range(1, x_end, step = 1)
plot(x, SLAC_solution["LMP"], label = "SLAC", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
plot!(x, DLAC_solution["LMP"][1:x_end], label = "DLAC-AVG")
plot!(x, DLAC_45_solution["LMP"][1:x_end], label = "DLAC-NLB-45")
xticks!(0:24:x_end)