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
- Make sure the first time point is the same for all scenarios
- Normalize the time series data

# NY Grid TODO
- [NY_Sienna_Conversion](https://github.com/gackermannlogan/NY_Sienna_Conversion)
- Thermal Generators operation cost (start-up, shut-down, no-load cost)
- Batteries
- Time series data (wind, solar, load, gas price)

# Questions
- Generation cost: Heat rate, TwoPartCost, ThreePartCost, MarketBids?
    - ThreePartCost: Fixed cost, variable cost, and start-up cost
- [ThermalStandard](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/generated_ThermalStandard/#ThermalStandard)

