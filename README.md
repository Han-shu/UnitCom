# UnitCom

UnitCom.jl is a Julia package for the unit commitment problem. You can either run a rolling horizon UC or a rolling horzion UC together with ED.

## Data availability
Data used in the code can be downloaded from [Data](https://doi.org/10.5281/zenodo.14952623)
## Usage
- Download the data from the link provided above.
- Specify the path to the *Data folder* in the `Data_dir` variable in the `NYGrid/manual_data_entries.jl` file line 3.
- `run_UC.jl` and `run_UC_ED.jl` are the main files to run the code.
- Specify the following parameters 
```julia
POLICY =  # select from "SB", "PF", "MF", "BF","WF", "DR60", "DR30" 
run_date = Date(2025,3,6) # Sepecify the date of the run
res_dir = "Result" # Specify the directory to save the results
uc_horizon = 36 
```
