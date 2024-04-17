using Plots
DLAUC_solution = read_json(joinpath(result_dir, "DLAUC_solution_2024-04-17.json"))
SLAUC_solution = read_json(joinpath(result_dir, "SLAUC_solution_2024-04-17.json"))
DLAUC_45_solution = read_json(joinpath(result_dir, "DLAUC_45_solution_2024-04-17.json"))
LMP = solution["LMP"]
x_end = length(SLAUC_solution["LMP"])
x = range(1, x_end, step = 1)
plot(x, SLAUC_solution["LMP"], label = "SLAUC", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
plot!(x, DLAUC_solution["LMP"][1:x_end], label = "DLAUC-AVG")
plot!(x, DLAUC_45_solution["LMP"][1:x_end], label = "DLAUC-NLB-45")
xticks!(0:10:x_end)