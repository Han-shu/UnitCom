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
S_UCED_file = joinpath(result_dir, "UCED_sol_2024-05-05.json")
ED_S_UCED_file = joinpath(result_dir, "ED_sol_2024-05-05.json")
S_UCED_sol = read_json(uc_sol_file)
ED_S_UCED_sol = read_json(ed_sol_file)
S_UCED_LMP = S_UCED_sol["Hourly average LMP"]
ED_S_UCED_LMP = []
for i in ED_S_UCED_sol["LMP"]
    append!(ED_S_UCED_LMP, i)
end
hour_x= range(1, length(S_UCED_LMP), step = 1)
min5_x= range(1/12, length(S_UCED_LMP), step = 1/12)
plot(min5_x, ED_S_UCED_LMP, label = "ED_S-UCED", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)#, legend = :outertopright)
plot!(hour_x, S_UCED_LMP, label = "S-UCED")


AVG_UCED_file = joinpath(result_dir, "AVG-UCED_2024-05-06.json")
AVG_UCED_sol = read_json(AVG_UCED_file)
AVG_UCED_LMP = AVG_UCED_sol["Hourly average LMP"]

ED_AVG_UCED_file = joinpath(result_dir, "ED_AVG-UCED_2024-05-06.json")
ED_AVG_UCED_sol = read_json(ED_AVG_UCED_file)
ED_AVG_UCED_LMP = []
for i in ED_AVG_UCED_sol["LMP"]
    append!(ED_AVG_UCED_LMP, i)
end
min5_x= range(1/12, length(AVG_UCED_LMP), step = 1/12)
plot(min5_x, ED_AVG_UCED_LMP, label = "ED_AVG-UCED", xlabel = "Hour", ylabel = "Price (\$/MW)", title = "LMP", guidefontsize=12, tickfontsize=8, legendfontsize=11)
hour_x= range(1, length(AVG_UCED_LMP), step = 1)
plot!(hour_x, AVG_UCED_LMP, label = "AVG-UCED")
