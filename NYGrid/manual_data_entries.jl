reserve_requirement = Dict(
    "spin10" => 985,
    "res10" => 2630,
    "res30" => 5500,
)

reserve_short_penalty = Dict(
    "spin10" => 1000,
    "res10" => 500,
    "res30" => 100,
)

map_UnitType = Dict(
    "Combustion Turbine" => PrimeMovers.CT,
    "Combined Cycle" => PrimeMovers.CC,
    "Internal Combustion" => PrimeMovers.IC,
    "Steam Turbine" => PrimeMovers.ST,
    "Jet Engine" => PrimeMovers.GT,
    "Nuclear" => PrimeMovers.ST,
)

map_FuelType = Dict(
    "Kerosene" => ThermalFuels.NATURAL_GAS,
    "Natural Gas" => ThermalFuels.NATURAL_GAS,
    "Fuel Oil 2" => ThermalFuels.DISTILLATE_FUEL_OIL,
    "Coal" => ThermalFuels.COAL,
    "Fuel Oil 6" => ThermalFuels.RESIDUAL_FUEL_OIL,
    "Nuclear" => ThermalFuels.NUCLEAR,
    )

coal_size_lims = Dict(
    "SMALL" => 300,
    "LARGE" => 900,
    #SUPER" => larger than 900
)

# Adapted from https://www.wecc.org/Reliability/1r10726%20WECC%20Update%20of%20Reliability%20and%20Cost%20Impacts%20of%20Flexible%20Generation%20on%20Fossil.pdf Table 2
duration_lims = Dict(
    ("CLLIG", "SMALL") => (up = 12.0, down = 6.0), # Coal and Lignite -> WECC (1) Small coal
    ("CLLIG", "LARGE") => (up = 12.0, down = 8.0), # WECC (2) Large coal
    ("CLLIG", "SUPER") => (up = 24.0, down = 8.0), # WECC (3) Super-critical coal
    "CCGT90" => (up = 2.0, down = 6.0),    # Combined cycle greater than 90 MW -> WECC (7) Typical CC
    "CCLE90" => (up = 2.0, down = 4.0), # Combined cycle less than 90 MW -> WECC (7) Typical CC, modified
    "GSNONR" => (up = 2.0, down = 4.0), # Gas steam non-reheat -> WECC (4) Gas-fired steam (sub- and super-critical)
    "GSREH" => (up = 2.0, down = 4.0), # Gas steam reheat boiler -> WECC (4) Gas-fired steam (sub- and super-critical)
    "GSSUP" => (up = 2.0, down = 4.0), # Gas-steam supercritical -> WECC (4) Gas-fired steam (sub- and super-critical)
    "SCGT90" => (up = 1.0, down = 1.0), # Simple-cycle greater than 90 MW -> WECC (5) Large-frame Gas CT
    "SCLE90" => (up = 1.0, down = 0.0), # Simple-cycle less than 90 MW -> WECC (6) Aero derivative CT
    "NUCLEAR" => (up = 8760.0, down = 8760.0), # Nuclear
)

function _thermal_type(pm, fuel, pmax)
    if pm == PrimeMovers.CT
        if pmax > 90
            return "SCGT90"
        else
            return "SCLE90"
        end
    elseif pm == PrimeMovers.CC
        if pmax > 90
            return "CCGT90"
        else
            return "CCLE90"
        end
    elseif pm == PrimeMovers.IC
        return "SCLE90"
    elseif pm == PrimeMovers.ST
        if fuel == ThermalFuels.COAL
            if pmax > 900
                return ("CLLIG", "SUPER")
            elseif pmax > 300
                return ("CLLIG", "LARGE")
            else
                return ("CLLIG", "SMALL")
            end
        elseif fuel == ThermalFuels.NUCLEAR
            return "NUCLEAR"
        else
            return "GSNONR"
        end
    elseif pm == PrimeMovers.GT
        return "GSNONR"
    end 
end

function _thermal_start_up_cost(pm, pmax)
    if pm == PrimeMovers.CC
        if pmax <= 200
            return 0
        else
            return 50*pmax
        end
    elseif pm == PrimeMovers.IC
        if pmax >= 4
            return 0
        else
            return 3.3*pmax
        end
    elseif pm == PrimeMovers.ST
        return 60*pmax
    elseif pm == PrimeMovers.GT
        return 50*pmax
    elseif pm == PrimeMovers.CT
        return 20*pmax
    end
end