wind_gens = collect(get_components(x -> x.prime_mover_type == PrimeMovers.WT, RenewableGen, system))
solar_gens = collect(get_components(x -> x.prime_mover_type == PrimeMovers.PVe, RenewableGen, system))
loads = collect(get_components(StaticLoad, system))

scenario_cnt = 10
time_steps = 1:48
init_time = DateTime(2019, 1, 1, 0)
net_inj_dict = Dict()
for i in 1:10
    start_time = init_time + Dates.Hour(i-1)
    net_inj = zeros(length(time_steps), scenario_cnt)
    net_inj -= get_time_series_values(Scenarios, loads[1], "load", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
    net_inj += get_time_series_values(Scenarios, solar_gens[1], "solar_power", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
    net_inj += get_time_series_values(Scenarios, wind_gens[1], "wind_power", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
    net_inj_dict[i] = net_inj
end

# get_time_series(Scenarios, loads[1], "load", start_time = start_time, len = length(time_steps), count = 2)
# get_time_series_values(Scenarios, loads[1], "load", start_time = start_time, len = length(time_steps), ignore_scaling_factors = true)
# get_time_series_array(Scenarios, loads[1], "load", start_time = start_time, len = length(time_steps))

thermal_gen_names = get_name.(get_components(ThermalGen, system))
for g in thermal_gen_names
    for i in eachindex(solution["Generator energy dispatch"][g])
        if solution["Generator energy dispatch"][g][i] > 0
            println("$(g) $(i) $(solution["Generator energy dispatch"][g][i])")
        end
    end
end
