# Load the system data
include("case5_re.jl")
include("stochastic_uc.jl")
include("save_results.jl")

initial_time = Dates.DateTime(2018, 1, 1)
horizon = 24
total_elapsed_time = 0.0
init_value = _get_init_value(system)
LMP = OrderedDict{DateTime, Float64}()
for i in 1:10 #8712
    global total_elapsed_time, init_value, LMP
    start_time = initial_time + Dates.Hour(i-1)
    @info "Running rolling horizon UC for $(start_time)"
    elapsed_time = @elapsed begin
        model = stochastic_uc(system, HiGHS.Optimizer, init_value = init_value, 
                    start_time = start_time, scenario_count = 10, horizon = horizon)
        init_value = _get_init_value(system, model)  
    end
    LMP = compute_LMP(system, model, LMP)
    @info "Running UC for $(start_time) takes: $elapsed_time seconds"
    total_elapsed_time += elapsed_time
end
@info "Total elapsed time: $total_elapsed_time seconds"


