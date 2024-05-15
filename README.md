# UnitCom

# Limitations
- All thermal generators and batteries are assumed to be eligible to provide reserve
- Reserve is provided by thermal generators and batteries only
- Variable cost of thermal generators is assumed to be constant
- No minimum run time and notification time
- Hydro power plants are modeled by SingleTimeSeries historical dispatch

# Problems
- UC infeasibility if starting from existing solution files
- Fixed: UC unbounded when setting theta = 8, 7, 6 (curtailment or overgeneration)

# Log
May 13
- Use the dual of storage energy balance constraint as the residual value of storage
May 12
- Specify Nuclear gen as must run 
- Save uc_sol and ed_sol for every month and reinitiate uc_sol and ed_sol
- Fix the length for UCInitValue.history_vg (24) and UCInitValue.history_wg (8)
May 10
- _get_ed_price *12 => $/MWh
May 9
- Storage energy capacity MWh and power rating MW, fix constraints of reserve provided by storage
- Fix objective function of ED (divide 12 for 5 min)
May 8
- Add hydro power plants
- Add residual values for storage
May 7
- Rank existing 10 scenarios by net load sum
- generate_hy_ts.jl to process NYISO historical real-time hydro time series data
May 1
- Fixing ramp rate, up = RAMP_30, down = RAMP_10, RAMP_30*2 for hourly ramping
- Fixing storage energy and power rating (/Sienna base power)
April
- Add reserve (10 min spinning, 10 min and 30 min reserve)
- Adding Thermal start-up cost by finding the the most like gen in PERC gen data (cosine similarity)
- Add deterministic version of the model
- Replicate Jacob's policy and results




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



