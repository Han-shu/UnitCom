#DESCRIPTION: In this portion of the code, will be building wind, solar, and battery
# All functions follow similar structure: 
# 1. Create respective component (wind, solar, battery or load) with specified paramters
# 2. Add the component to the power system 
# 3. Add a time series for the maximum actie power based on the input time series data 
# 4. Return newly created component 

#RUNTIME: 0.5 seconds
#OUTPUT: Build renewable fundtions 
#ISSUE: None

#   Created by Vivienne Liu, NREL
#   Modified by Gabriela Ackermann Logan, and Han Shu, Cornell University 
#   Last modified in March, 2024

using PowerSystems
const PSY = PowerSystems

#Function to generate a time array with hourly timestamps for a given year
get_timestamp(year) = DateTime("$(year)-01-01T00:00:00"):Hour(1):DateTime("$(year)-12-31T23:55:00")


#Function builds a battery component in the power system. it takes arugments such as system, type of storage device ('::Type{T}), 
#the bus where the battery component is loacted, its name, energy capacity, rating and efficiency
function _build_battery(sys, ::Type{T}, bus::PSY.Bus, name, energy_capacity, rating, efficiency) where {T<:PSY.Storage}

    # Create a new storage device of the specified type
    device = T(
        name=name,                         # Set the name for the new component
        available=true,                    # Mark the component as available
        bus=bus,                           # Assign the bus to the component
        prime_mover_type=PSY.PrimeMovers.BA,    # Set the prime mover to Battery
        initial_energy = energy_capacity / 2,  # Set initial energy level
        state_of_charge_limits=(min=0, max=energy_capacity),  # Set state of charge limits
        rating=rating,                     # Set the rating
        active_power=rating,               # Set active power equal to rating
        input_active_power_limits=(min=0.0, max=rating),  # Set input active power limits
        output_active_power_limits=(min=0.0, max=rating),  # Set output active power limits
        efficiency=(in=efficiency, out=efficiency),  # Set efficiency
        reactive_power=0.0,                # Set reactive power
        reactive_power_limits=nothing,      # No reactive power limits
        base_power=100.0,                    # Set base power
        operation_cost=StorageManagementCost(
            VariableCost(0.0),
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        )
    )

    # Add the battery component to the power system
    PSY.add_component!(sys, device)

    return device  # Return the newly created battery component
end

#Function builds a load component in the power system. it takes arugments such as system, bus, name, load_ts and load_eyear, 
function _build_load(sys, bus::PSY.Bus, name, load_ts, load_year)
    # Create a new load component with the specified parameters
    load = PSY.StandardLoad(
        name=name,                         # Set the name for the new component
        available=true,                    # Mark the component as available
        bus=bus,                           # Assign the bus to the component
        base_power=100.0,                  # Base power of the load component (in kW)
        max_constant_active_power=maximum(load_ts) / 100,  # Maximum constant active power of the load component (scaled from the maximum of the load time series)
    )

    # Add the load component to the power system model
    add_component!(sys, load)
    #ISSUE SEEMS TO BE HERE ************************************************************************************************************
    ### The issue was that the name of the time series and the name in the renewable config doesn't match. Now they matched but we should think about how to name things later to make it easier to track.
    # Add a time series for the load, scaling the load based on the maximum active power specified by the time series
    #=
    PSY.add_time_series!(
        sys,
        load,
        PSY.SingleTimeSeries(
            "max_active_power",  # Name of the time series for the maximum active power
            TimeArray(get_timestamp(load_year), load_ts);  # Time series data for the load
            scaling_factor_multiplier=PSY.get_max_active_power,  # Scaling factor based on the maximum active power
        ),
    )

    =#
    if maximum(load_ts) == 0.0
        PSY.add_time_series!(
            sys,
            load,
            PSY.SingleTimeSeries(
                "max_active_power",
                TimeArray(get_timestamp(load_year), load_ts),
                scaling_factor_multiplier=PSY.get_max_active_power,
            )
        )
    else
        PSY.add_time_series!(
            sys,
            load,
            PSY.SingleTimeSeries(
                "max_active_power",
                TimeArray(get_timestamp(load_year), load_ts / maximum(load_ts)),
                scaling_factor_multiplier=PSY.get_max_active_power,
            )
        )
    end

    return load  # Return the newly created load component
end


function _build_bus(sys, bus_id, name, bus_type, base_voltage)
    add_component!(
        sys,
        PSY.ACBus(bus_id, name, bus_type, 0, 1.0, (min=0.9, max=1.05), base_voltage, nothing, nothing),
    )
end

function _build_lines(sys; frombus::PSY.ACBus, tobus::PSY.ACBus, name, r, x, b, rating)
    # Create a new storage device of the specified type
    device = PSY.Line(
        name=name,
        available=true,
        active_power_flow=maximum(rating_ts) / 100.0,
        reactive_power_flow=0.0,
        arc=PSY.Arc(from=frombus, to=tobus),
        r=r,
        x=x,
        b=(from=b, to=b),
        rate=rating / 100.0,
        angle_limits=PSY.MinMax((-1.571, 1.571)),
    )
    PSY.add_component!(sys, device)
    return device
end

function _build_hvdc(sys; frombus::PSY.ACBus, tobus::PSY.ACBus, name, r, x, b, rating)
    # Create a new storage device of the specified type
    device = PSY.TModelHVDCLine(
        name=name,
        available=true,
        active_power_flow=rating / 100.0,
        arc=PSY.Arc(from=frombus, to=tobus),
        r=r,
        l=x,
        c=b,
        active_power_limits_from=PSY.MinMax((0, rating)),
        active_power_limits_to=PSY.MinMax((0, rating)),
    )
    PSY.add_component!(sys, device)
    return device
end

function _build_interface_flow(sys; name, rating, ifdict)
    # Create a new storage device of the specified type
    device = PSY.TransmissionInterface(
        name=name,
        available=true,
        active_power_limits=PSY.MinMax((-rating, rating)),
        violation_penalty=0.0,
        direction_mapping=ifdict
    )
    PSY.add_component!(sys, device)
    return device
end

function _add_hydro(
    sys::PSY.System,
    bus::PSY.Bus;
    name::AbstractString,
    pmin::Float64,
    pmax::Float64, 
    ramp_10::Float64, 
    ramp_30::Float64, 
    cost::PSY.OperationalCost,
    )
    base_power = get_base_power(sys)
    device = PSY.HydroDispatch(
        name = name,
        available = true,
        bus = bus,
        active_power = 0.0,
        reactive_power = 0.0,
        rating = pmax / base_power,
        prime_mover_type = PSY.PrimeMovers.HY,
        active_power_limits = PSY.MinMax((pmin/base_power, pmax/base_power)),
        reactive_power_limits=nothing,
        ramp_limits = (up=ramp_10/base_power, down=ramp_30/base_power), 
        time_limits = nothing,
        base_power = base_power,
        operation_cost = cost,
        ext = Dict{String,Any}(),
    )
    PSY.add_component!(sys, device)
    return device
end



function _add_thermal(
    sys,
    bus::PSY.Bus;
    name,
    fuel::PSY.ThermalFuels,
    pmin,
    pmax,
    ramp_10,
    ramp_30,
    cost::PSY.OperationalCost,
    pm::PSY.PrimeMovers,
    uptime,
    downtime,
)
    base_power = get_base_power(sys)
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
        active_power_limits=PSY.MinMax((pmin/base_power, pmax/base_power)),
        reactive_power_limits=nothing,
        ramp_limits=(up=ramp_10/base_power, down=ramp_30/base_power),
        time_limits=(up=uptime, down=downtime),
        operation_cost=cost,
        must_run = fuel == ThermalFuels.NUCLEAR ? true : false,
        base_power=base_power,
        time_at_status=999.0,
        ext=Dict{String,Any}(),
    )
    PSY.add_component!(sys, device)

    return device  # Return the newly created component
end
