# UnitCom

# Limitations
- Reserve requirement is constant for all time points
- All thermal generators and batteries are assumed to be eligible to provide reserve
- Reserve is provided by only thermal generators and batteries
- Variable cost of thermal generators is assumed to be constant
- No minimum run time and notification time
- No hydro power plants (or modeling by static dispatch)

# April 11 - 17 TODO
- ~~Run rolling horizon with solution from previous time point~~
- ~~Investigate the infeasibility at DateTime(2019,1,1,13)~~
- ~~Add deterministic version of the model~~
- ~~Thermal start-up cost by finding the the most like gen in PERC gen data (cosine similarity)~~
- Replicate Jacob's policy and results
- ~~Add reserve~~
    - ~~reserve requirement~~
    - ~~reserve variables for thermal gen and battery~~

# Model TODO
- ~~Deterministic version~~
- ~~Add reserve as current implementations in NYISO~~
    - ~~10 min spinning ~~
    - ~~10 min non-synchronized ~~
    - ~~30 min reserve (spinning + non-synchronized)~~
- New reserve product in NYISO, 60 min, 4 hour notice
- Add hydro power plants: historical data as fixed dispatch

# Time series TODO
- Generate time series with NYISO data
- Make sure the first time point is the same for all scenarios (or take average when attaching ts to components)
- ~~Normalize the time series data (divide by the base power)~~

# NY Grid TODO
- [NY_Sienna_Conversion](https://github.com/gackermannlogan/NY_Sienna_Conversion)
- Thermal Generators operation cost 
    - Heat rate, TwoPartCost, ThreePartCost, MarketBids?
    - ThreePartCost: Fixed cost, variable cost, and start-up cost
    - Need: start-up
            shut-down = 0 or 0.2*start_up 
    - heat rate * fuel cost
    - differenciate nuclear, thermal_st, thermal
- ~~ThermalGen time_limits (min up and down time)~~
- ~~Battery~~
- Hydro
- ~~Time series data (wind, solar, load)~~



