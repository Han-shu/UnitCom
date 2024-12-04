# UnitCom

# Key model improvements compared with INFORMS results
    - Add imports supply curve as in add_imports.jl
    - Add residual value for PH in UC 
    - Energy storage eb_t0 initialization in UC and ED
    - Exclude nuclear to provide reserve

# Other model improvements to consider
    - Increase VOLL: 5,000 -> 200,000
    - Increase renewable generaition: solar*10, wind*1.38
    - Imporve operational cost of thermal generators by using piecewise linear cost function
    - Increase reserve requirement of DR
    - Decrease ramp rate

# Result Description
- 2024-10-18 (presented on INFORMS)
    - VOLL = 5,000, solar*1, wind*1
    - cost = ThreePartCost(gen_cost.COST_1, gen_cost.COST_0, genprop.PERC_StartUpCost, 0.0)
- Before 2024-11-19
    - Storage SOC is not initialized correctly in INFORMS results, leading to the high profits and same profits per MW for BA and PH
    - After correcting the SOC initialization, BA and PH are not working as expected
    - From results between 2024-11-15 and 2024-11-18, I found the residual value (dual of storage soc transition) used in the objective of ED is negative. Hence, BA and PH always discharge
    - 2024-11-15: consider variable cost in UC, no start-up cost, no-load cost
    - 2024-11-16: Remove minup and mindown constraints
    - 2024-11-17: Initialize eb_t0 in UC and ED
    - 2024-11-18: Remove storage 
- 2024-11-19
    - Change the sign of residual value of storage in ED objective function
    - Constant imports 2900 MW in UC and ED
    - Results: PH is always at low SOC
- 2024-12-01
    - Add imports supply curve as in add_imports.jl
    - Add residual value for PH in UC 
    - Results: Better PH action, PH is more profitable (per unit) than BA
- 2024-12-03
    - Overestimate the residual value
    - ED obj: storage_value[b]*12 -> storage_value[b]

- 2024-11-01
    - VOLL = 5,000, solar*10, wind*1.38
    - cost = ThreePartCost(gen_cost.COST_1, max(-gen.PMIN*gen_cost.COST_1, gen_cost.COST_0), genprop.StartUpCost, 0.0)
- 2024-11-02 
    - VOLL = 200,000, solar*10, wind*1.38
    - cost = ThreePartCost(gen_cost.COST_1, max(-gen.PMIN*gen_cost.COST_1, gen_cost.COST_0), genprop.StartUpCost, 0.0)
    - Exclude nuclear to provide reserve
    - Run new policy -- DR30: Add reserve requirment of DR to 30T
- 2024-11-09
    - VOLL = 5,000, solar*10, wind*1.38
    - cost = ThreePartCost(gen_cost.COST_1, max(-gen.PMIN*gen_cost.COST_1, gen_cost.COST_0), genprop.StartUpCost, 0.0)
    - Exclude nuclear to provide reserve
    - Modify energy storage eb_t0
- 2024-11-11
    - VOLL = 5,000
    - solar*1, wind*1
    - cost = ThreePartCost(gen_cost.COST_1, max(-gen.PMIN*gen_cost.COST_1, gen_cost.COST_0), genprop.StartUpCost, 0.0)
    - Exclude nuclear to provide reserve
    - Modify energy storage eb_t0
    - Add back nuclear plants
- 2024-11-13 (INFORMS results setting but Exclude nuclear to provide reserve and Modify energy storage eb_t0)
    - VOLL = 5,000
    - solar*1, wind*1
    - cost = ThreePartCost(gen_cost.COST_1, gen_cost.COST_0, genprop.PERC_StartUpCost, 0.0)
    - Add back nuclear plants
- 2024-11-14 (INFORMS results setting but Exclude nuclear to provide reserve and Modify energy storage eb_t0)
    - VOLL = 5,000
    - solar*1, wind*1
    - cost = ThreePartCost(gen_cost.COST_1, gen_cost.COST_0, genprop.PERC_StartUpCost, 0.0)
    - Add back nuclear plants
    - Add 2900 MW imports


# Storage Capacity
"In 2019, New York passed the nation-leading Climate Leadership and Community Protection Act (Climate Act), which codified some of the most aggressive energy and climate goals in the country, including 1,500 MW of energy storage by 2025 and 3,000 MW by 2030. In June 2024, New York’s Public Service Commission expanded the goal to 6,000 MW by 2030." (https://www.nyserda.ny.gov/All-Programs/Energy-Storage-Program)
- PH => Pumped hydro (treat as 10h battery): 1170 MWh
    approximately how many cycles the Blenheim-Gilboa plant has per year
    281.7 GWh/(10 hrs*1160 MW)=24 cycles
- BA => 4h battery: 1500 MWh


# Limitations
- Reserve qualification
    - Spinning reserve: Online thermal generators and all batteries
    - Non-spinning reserve: Offline fast-start thermal generators (min up time <= 1 hr)
    - Thermal generators are not allowed to provide any reserve
- Variable cost of thermal generators is assumed to be constant
- No minimum run time and notification time
- Hydro power plants are modeled by SingleTimeSeries historical dispatch

# Problems
- RLMP (fix integer variables) v.s. ELMP (relax integer variables)

# Log
September 20 2024
- Update data
- Add solar/wind/hydro profits
- Add curtailment 
- Stochastic without reserve
- 50 percentile of the net load or 50 percentile load and 50 percentile solar/wind respectively
- Reserve tunning (new product to address forecast error)
September 28
- Add new reserve products (60T)
May 13
- Use the dual of storage energy balance constraint as the residual value of storage
May 12
- Specify Nuclear gen as must run 
- Save uc_sol and ed_sol for every month and reinitiate uc_sol and ed_sol
- Fix the length for UCInitValue.history_vg (24) and UCInitValue.history_wg (8)
May 10
- _get_ED_dual_price *12 => $/MWh
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
- Add reserve (10S spinning, 10T and 30T reserve)
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
- Update to be compatible with the latest version of PowerSystems.jl



