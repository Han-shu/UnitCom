# UnitCom

# Model TODO
- Deterministic version
- Add reserve as current implementations in NYISO
    - 10 min spinning 
    - 10 min non-synchronized 
    - 30 min reserve (spinning + non-synchronized)
- New reserve product in NYISO, 60 min, 4 hour notice
- Add tests

# Time series TODO
- Generate time series with NYISO data
- Make sure the first time point is the same for all scenarios (or take average when attaching ts to components)
- ~~Normalize the time series data (divide by the base power)~~

# NY Grid TODO
- [NY_Sienna_Conversion](https://github.com/gackermannlogan/NY_Sienna_Conversion)
- Thermal Generators operation cost 
    - Heat rate, TwoPartCost, ThreePartCost, MarketBids?
    - ThreePartCost: Fixed cost, variable cost, and start-up cost
    - Need: start-up, shut-down, no-load cost
    - heat rate * fuel cost
- ThermalGen time_limits (min up and down time)
- ~~Battery~~
- ~~Time series data (wind, solar, load)~~

```
mutable struct ThreePartCost <: OperationalCost
    variable::VariableCost
    fixed::Float64
    start_up::Float64
    shut_down::Float64
end
```


```
device = PSY.ThermalStandard(
        name=name,
        available=true,
        status=true,
        bus=bus,
        active_power=0.0,
        reactive_power=0.0,
        rating=pmax / base_power,
        prime_mover_type=pm,
        fuel=fuel,
        active_power_limits=PSY.MinMax((pmin, pmax)),
        reactive_power_limits=nothing,
        ramp_limits=(up=ramp_rate, down=ramp_rate),
        time_limits=(up=1.0, down=1.0),
        operation_cost=cost,
        base_power=base_power,
        time_at_status=999.0,
        ext=Dict{String,Any}(),
    )
```
