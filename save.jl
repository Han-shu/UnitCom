save_date = Date(year(uc_time), month(uc_time), 1)
uc_sol_file = joinpath(result_dir, master_folder, uc_folder, "UC_$(save_date).json")
ed_sol_file = joinpath(result_dir, master_folder, ed_folder, "ED_$(save_date).json")
@info "Saving the solutions to $(uc_sol_file) and $(ed_sol_file)"
write_json(uc_sol_file, uc_sol)
write_json(ed_sol_file, ed_sol)