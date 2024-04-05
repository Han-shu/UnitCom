# UnitCom

# TODO
- Add reserve as current implementations in NYISO
    - 10 min spinning 
    - 10 min non-synchronized 
    - 30 min reserve (spinning + non-synchronized)
- New reserve product in NYISO, 60 min, 4 hour notice
- Add tests

# NY Grid
- [NYISO](https://www.nyiso.com/)
- Thermal Generators (gas price*heat rate or piecewise linear or quadratic)
- Aggregate wind and solar (create one component for each located in a selected bus)
- Batteries
- Time series data (wind, solar, load, gas price)
- Construct network but do not use it (single bus)

# Questions
- mpc2050.m contains mpc_gen and mpc_gencost. How to get mpc2050.m? Use mpc_gen and mpc_gencost from MATPOWER?
- What are the data for the thermal generators? 
- Generation cost: Heat rate, TwoPartCost, ThreePartCost, MarketBids?
- [ThermalStandard](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/generated_ThermalStandard/#ThermalStandard)
- [ThermalMultiStart](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/generated_ThermalMultiStart/)

```
mutable struct ThermalStandard <: ThermalGen
    name::String
    available::Bool
    status::Bool
    bus::ACBus
    active_power::Float64
    reactive_power::Float64
    rating::Float64
    active_power_limits::MinMax
    reactive_power_limits::Union{Nothing, MinMax}
    ramp_limits::Union{Nothing, UpDown}
    operation_cost::OperationalCost
    base_power::Float64
    time_limits::Union{Nothing, UpDown}
    must_run::Bool
    prime_mover_type::PrimeMovers
    fuel::ThermalFuels
    services::Vector{Service}
    time_at_status::Float64
    dynamic_injector::Union{Nothing, DynamicInjection}
    ext::Dict{String, Any}
    time_series_container::InfrastructureSystems.TimeSeriesContainer
    internal::InfrastructureSystemsInternal
end
```