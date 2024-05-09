using Plots
hydro_file = "/Users/hanshu/Desktop/Price_formation/Data/NYGrid/hydro_2019.csv"
df_ts = CSV.read(hydro_file, DataFrame)
plot(df_ts.Gen_MW[1:5000], label="hydro")