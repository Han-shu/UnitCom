using Plots

solution = read_json(joinpath(result_dir, "UC_solution20240416.json"))
LMP = solution["LMP"]
plot(LMP)
