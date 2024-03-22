using DataFrames, HDF5

function read_hdf(key, file_path)
    h5open(file_path, "r") do file
        return read(file[key])
    end
end



path = "/Users/hanshu/Desktop/Price_formation/Data/"
load_path = path*"BA_load_actuals_2018.h5"
solar_path = path*"BA_solar_actuals_2018.h5"
wind_path = path*"BA_wind_actuals_2018.h5"

load_values = read_hdf("actuals", load_path)
solar_values = read_hdf("actuals", solar_path)
wind_values = read_hdf("actuals", wind_path)
solar_metadata = read_hdf("meta", solar_path)

for i in eachindex(solar_metadata)
    println(solar_metadata[i][:site_ids])
end

sum(solar_values[:,105120])
solar_metadata[2].ISO
collect(keys(solar_metadata[1]))