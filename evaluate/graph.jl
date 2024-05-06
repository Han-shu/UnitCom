using Plots
DLAC_solution = read_json(joinpath(result_dir, "DLAC_sol_2024-04-17.json"))
SLAC_solution = read_json(joinpath(result_dir, "SLAC_sol_2024-04-17.json"))
DLAC_40_solution = read_json(joinpath(result_dir, "DLAC-NLB-40_sol_2024-04-17.json"))
DLAC_45_solution = read_json(joinpath(result_dir, "DLAC-NLB-45_sol_2024-04-17.json"))
DLAC_50_solution = read_json(joinpath(result_dir, "DLAC-NLB-50_sol_2024-04-17.json"))
LMP = solution["LMP"]
x_end = length(SLAC_solution["LMP"])
x = range(1, x_end, step = 1)
plot(x, SLAC_solution["LMP"], label = "SLAC", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
# plot!(x, DLAC_solution["LMP"][1:x_end], label = "DLAC-AVG")
plot!(x, DLAC_40_solution["LMP"][1:x_end], label = "DLAC-NLB-40")
plot!(x, DLAC_45_solution["LMP"][1:x_end], label = "DLAC-NLB-45")
plot!(x, DLAC_50_solution["LMP"][1:x_end], label = "DLAC-NLB-50")
xticks!(0:24:x_end)

result_dir = "/Users/hanshu/Desktop/Price_formation/Result"
uc_sol_file = joinpath(result_dir, "UCED_sol_$(Dates.today()).json")
ed_sol_file = joinpath(result_dir, "ED_sol_$(Dates.today()).json")
uc_sol = read_json(uc_sol_file)
ed_sol = read_json(ed_sol_file)
LMP = uc_sol["Hourly average LMP"]
x= range(1, length(LMP), step = 1)
plot(x, LMP, label = "UCED", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", ylims=[0,100], guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)