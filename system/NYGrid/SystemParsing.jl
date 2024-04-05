using PowerSystems
using CSV
using DataFrames
using Dates
using TimeSeries
using InfrastructureSystems
using PowerSystems
const PSY = PowerSystems

include("parsing_utils.jl")

base_power = 100
system = PSY.System(base_power)
set_units_base_system!(system, PSY.UnitSystem.NATURAL_UNITS)

# Add single bus
_build_bus(system, 1, "bus_1", 2, 345)

# Add renewables
solar_rating, wind_rating = 1000, 1000
@info "Adding renewables with pwoer rating of $solar_rating and $wind_rating MW"
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


# Add thermal generators
map_UnitType = Dict(
    "Combustion Turbine" => PrimeMovers.CT,
    "Combined Cycle" => PrimeMovers.CC,
    "Internal Combustion" => PrimeMovers.IC,
    "Steam Turbine" => PrimeMovers.ST,
    "Jet Engine" => PrimeMovers.GT,
    "Nuclear" => PrimeMovers.ST,
)

map_FuelType = Dict(
    "Kerosene" => ThermalFuels.NATURAL_GAS,
    "Natural Gas" => ThermalFuels.NATURAL_GAS,
    "Fuel Oil 2" => ThermalFuels.DISTILLATE_FUEL_OIL,
    "Coal" => ThermalFuels.COAL,
    "Fuel Oil 6" => ThermalFuels.RESIDUAL_FUEL_OIL,
    "Nuclear" => ThermalFuels.NUCLEAR,
    )

gen_header = ["GEN_BUS", "PG", "QG", "QMAX", "QMIN", "VG", "MBASE", "GEN_STATUS", "PMAX", "PMIN", "PC1", "PC2", "QC1MIN", "QC1MAX", "QC2MIN", "QC2MAX", "RAMP_AGC", "RAMP_10", "RAMP_30", "RAMP_Q", "APF"]
gencost_header = ["MODEL", "STARTUP", "SHUTDOWN", "NCOST", "COST_1", "COST_0"]
gen_dir = "/Users/hanshu/Desktop/Price_formation/UnitCom/system/NYGrid/Data"
df_gen = CSV.read(joinpath(gen_dir, "gen_2019.csv"), DataFrame, header = gen_header)
df_gencost = CSV.read(joinpath(gen_dir, "gencost_2019.csv"), DataFrame, header = gencost_header)
df_geninfo = CSV.read(joinpath(gen_dir, "geninfo.csv"), DataFrame)
df_genprop = CSV.read(joinpath(gen_dir, "gen_prop.csv"), DataFrame)
for (gen_id, gen) in enumerate(eachrow(df_gen))
    if gen_id > 233 #1-227: Thermal, 228-233: Nuclear
        break
    end
    if gen_id <= size(df_geninfo, 1)
        fuel = map_FuelType[df_geninfo[gen_id, "FuelType"]]
    else
        fuel = ThermalFuels.NUCLEAR
    end
    genprop = df_genprop[gen_id, :]
    gen_cost = df_gencost[gen_id, :]
    # bus = get_bus(system, gen.GEN_BUS)
    bus = get_bus(system, 1)
    name = genprop.GEN_NAME
    pmax = gen.PMAX
    pmin = gen.PMIN
    ramp_rate = gen.RAMP_10
    cost = TwoPartCost(gen_cost.COST_1, gen_cost.COST_0)
    pm = map_UnitType[genprop.GEN_FUEL]
    add_thermal(system, bus, name = name, fuel = fuel, pmin = pmin, pmax = pmax, ramp_rate = ramp_rate, cost = cost, pm = pm)
end

include("add_ts.jl")


