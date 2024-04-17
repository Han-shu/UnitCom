using Plots

solution = read_json(joinpath(result_dir, "UC_solution20240416_2.json"))
LMP = solution["LMP"]
x = range(1, length(LMP), step = 1)
plot(x, LMP, label = "stochastic", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
# plot!(x, LMP2, label = "deterministic")
xticks!(0:10:length(LMP))