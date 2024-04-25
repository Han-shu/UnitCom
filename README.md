# UnitCom

# Limitations
- All thermal generators and batteries are assumed to be eligible to provide reserve
- Reserve is provided by thermal generators and batteries only
- Variable cost of thermal generators is assumed to be constant
- No minimum run time and notification time
- No hydro power plants (or modeling by static dispatch)

# Problems
- Reserve price is always zero
    - All generators are assumed to be eligible to provide reserve
    - No cost to provide reserve 
- LMP is weird 
    - reaches the upper bound very often
    - negative -4XXX

# April 18 - 25 TODO
- Draft an email to ask NREL about the data issue
- Ramp rate correction
- Storage energy and power rarting
- Generate time series data for 5 min ED model
- ~~Add stochastic 5 min ED model (2h horizon)~~
- ~~Add 5min rolling horizon ED model~~
- ~~Connect ED model with UC model~~
    - pass commitment status from UC to ED
    - pass generartion dispatch and storage level from ED to UC
    - fix the first hour commitment of UC from last UC solution
- Get results from UC
    - ug, vg, wg at t = 2?
- Get results from ED 
    - pg, kb_charge, kb_discharge at t = 1
    - LMP at t = 1
- Go through the code and make sure everything is correct
- Calculate policy cost, charge, generator profits
- Replicate Jacob's policy
    - ~~DLAC-NLB-\theta~~
    - DLAC-RT-\theta
- Other policies ??? Discuss with Jacob
- NYISO new reserve product
    - 60 min, 4 hour reserves product

# April 11 - 17 TODO
- ~~Run rolling horizon with solution from previous time point~~
- ~~Investigate the infeasibility at DateTime(2019,1,1,13)~~
- ~~Add deterministic version of the model~~
- ~~Thermal start-up cost by finding the the most like gen in PERC gen data (cosine similarity)~~
- ~~Add reserve~~
    - ~~reserve requirement~~
    - ~~reserve shortfall penalty~~
    - ~~reserve variables for thermal gen and battery~~
- Replicate Jacob's policy and results
    - ~~SLAC~~
    - ~~DLAC-AVG~~
    - ~~DLAC-NLB-\theta~~
    - DLAC-RT-\theta
- ~~Add qunatile estimates time series data~~

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



