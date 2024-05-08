using PowerSystems
using CSV
using DataFrames
using Dates
using TimeSeries
using InfrastructureSystems
using PowerSystems
const PSY = PowerSystems


include("parsing_utils.jl")
include("manual_data_entries.jl")

function build_ny_system(; base_power = 100)::System
    data_dir = "/Users/hanshu/Desktop/Price_formation/Data/NYGrid"
    system = PSY.System(base_power)
    set_units_base_system!(system, PSY.UnitSystem.NATURAL_UNITS)

    # Add single bus
    _build_bus(system, 1, "bus_1", 2, 345)

    # Add renewables
    solar_rating, wind_rating = 1000, 1000
    solar = PSY.RenewableDispatch(
            name = "solar",  #sets name of solar component             
            available = true,   #marks the component as available       
            bus = get_bus(system,1), # assigns bus to which the solar ompnent is connected
            active_power = solar_rating / 100.0, # sets the active power of the solar component based on its rating 
            reactive_power = 0.0, #sets reatie power of solar component to zero 
            rating = solar_rating / 100.0, #sets rating of solar component 
            prime_mover_type=PSY.PrimeMovers.PVe, #sets the prime mover type as photovoltaic 
            reactive_power_limits=(min=0.0, max=1.0 * solar_rating / 100.0), #sets the reactive power limits
            power_factor=1.0, #sets the power factor to 1
            operation_cost=TwoPartCost(VariableCost(0.139), 0.0), #sets the operation cost of the solar component 
            base_power=100, #sets the base power to 0 
        )
    add_component!(system, solar)

    wind = PSY.RenewableDispatch(
            name = "wind",  #set name of wind component            
            available = true, #marks component as available 
            bus = get_bus(system, 1), #assigns bus to which wind component is connected 
            active_power = wind_rating / 100.0, #sets the active power wind component base on its rating 
            reactive_power = 0.0, #sets reative power of wind component to zero 
            rating = wind_rating / 100.0, #sets rating of wind component 
            prime_mover_type=PSY.PrimeMovers.WT, #sets the prime mover type of wind turbine
            reactive_power_limits=(min=0.0, max=1.0 * wind_rating / 100.0), #sets the reative power limits 
            power_factor=1.0, #sets the operation cost 
            operation_cost=TwoPartCost(nothing),
            base_power=100, #sets base power to 100 
        )
    add_component!(system, wind)

    # Add load
    load = PSY.StandardLoad(
            name = "load",                         # Set the name for the new component
            available = true,                    # Mark the component as available
            bus = get_bus(system, 1),                           # Assign the bus to the component
            base_power = 100.0,                  # Base power of the load component (in kW)
            # max_constant_active_power=maximum(load_ts) / 100,  # Maximum constant active power of the load component (scaled from the maximum of the load time series)
        )

    add_component!(system, load)

    # Add Battery
    storage = CSV.read(joinpath(data_dir, "StorageAssignment.csv"), DataFrame, header = ["Bus", "EnergyCapacity"])
    # Aggregate storage into one 
    eff = 0.9
    energy_capacity = 15 #sum(storage[:, :EnergyCapacity]) / 10000.0
    rating = energy_capacity * 0.25 # 4 hour battery
    bus = get_bus(system, 1)
    _build_battery(system, GenericBattery, bus, "BA", energy_capacity, rating, eff)  # Call build battery function

    # for (i, ba) in enumerate(eachrow(storage))
    #     eff = 0.9
    #     energy_capacity = ba.EnergyCapacity / 10000.0
    #     rating = energy_capacity * 0.25 # 4 hour battery
    #     bus = get_bus(system, 1)
    #     _build_battery(system, GenericBattery, bus, "BA_$i", energy_capacity, rating, eff)  # Call build battery function
    # end

    # Add thermal generators
    gen_header = ["GEN_BUS", "PG", "QG", "QMAX", "QMIN", "VG", "MBASE", "GEN_STATUS", "PMAX", "PMIN", "PC1", "PC2", "QC1MIN", "QC1MAX", "QC2MIN", "QC2MAX", "RAMP_AGC", "RAMP_10", "RAMP_30", "RAMP_Q", "APF"]
    gencost_header = ["MODEL", "STARTUP", "SHUTDOWN", "NCOST", "COST_1", "COST_0"]
    df_gen = CSV.read(joinpath(data_dir, "gen_2019.csv"), DataFrame, header = gen_header)
    df_gencost = CSV.read(joinpath(data_dir, "gencost_2019.csv"), DataFrame, header = gencost_header)
    df_geninfo = CSV.read(joinpath(data_dir, "geninfo.csv"), DataFrame)
    df_genprop = CSV.read(joinpath(data_dir, "gen_prop.csv"), DataFrame)
    df_nygen = CSV.read(joinpath(data_dir, "NY_gen.csv"), DataFrame)
    for (gen_id, gen) in enumerate(eachrow(df_gen))
        if gen_id > 233 #1-227: Thermal, 228-233: Nuclear
            break
        end
        if gen_id <= size(df_geninfo, 1)
            fuel = map_FuelType[df_geninfo[gen_id, "FuelType"]]
        else
            fuel = ThermalFuels.NUCLEAR
        end
        genprop = df_nygen[gen_id, :]
        gen_cost = df_gencost[gen_id, :]
        bus = get_bus(system, 1)
        name = genprop.GEN_NAME
        pmax = gen.PMAX
        pmin = gen.PMIN
        ramp_10 = gen.RAMP_10
        ramp_30 = gen.RAMP_30
        pm = map_UnitType[genprop.GEN_FUEL]
        # ThreePartCost(variable, fixed, start_up, shut_down)
        if fuel == ThermalFuels.NUCLEAR
            cost = ThreePartCost(gen_cost.COST_1, gen_cost.COST_0, genprop.StartUpCost, genprop.StartUpCost*100)
        else
            cost = ThreePartCost(gen_cost.COST_1, gen_cost.COST_0, genprop.StartUpCost, 0.0)
        end
        type = _thermal_type(pm, fuel, pmax)
        uptime, downtime = duration_lims[type][:up], duration_lims[type][:down]
        _add_thermal(system, bus; name = name, fuel = fuel, pmin = pmin, pmax = pmax, ramp_10 = ramp_10, ramp_30 = ramp_30, cost = cost, pm = pm, uptime = uptime, downtime = downtime)
    end

    # Add aggregate hydro
    _add_hydro(system, bus; name = "Hydro", pmin = 0.0, pmax = 5000.0, ramp_10 = 300.0, ramp_30 = 3000.0, cost = TwoPartCost(VariableCost(0.0), 0.0))

    return system
end