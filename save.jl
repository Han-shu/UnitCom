save_date = Date(uc_time)
uc_sol_file = joinpath(result_dir, master_folder, POLICY, uc_folder, "UC_$(save_date).json")
ed_sol_file = joinpath(result_dir, master_folder, POLICY, ed_folder, "ED_$(save_date).json")
@info "Saving the solutions to $(uc_sol_file) and $(ed_sol_file)"
write_json(uc_sol_file, uc_sol)
write_json(ed_sol_file, ed_sol)