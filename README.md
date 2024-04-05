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
- ~~Normalize the time series data (divide by the base power)~~

# NY Grid TODO
- [NY_Sienna_Conversion](https://github.com/gackermannlogan/NY_Sienna_Conversion)
- Thermal Generators operation cost 
    - Heat rate, TwoPartCost, ThreePartCost, MarketBids?
    - ThreePartCost: Fixed cost, variable cost, and start-up cost
    - Need: start-up, shut-down, no-load cost
    - heat rate * fuel cost
- ~~Battery~~
- ~~Time series data (wind, solar, load)~~
