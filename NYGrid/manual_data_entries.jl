# Reserve short penalty
# link: https://www.nyiso.com/documents/20142/9622070/Ancillary%20Services%20Shortage%20Pricing_study%20report.pdf
include("../src/structs.jl")
reserve_short_penalty = Dict(
    "10Spin" => [PriceMW(775, 655), PriceMW(25, 330)],
    "10Total" => [PriceMW(775, 1200), PriceMW(750, 1310), PriceMW(25, 650)],
    "30Total" => [PriceMW(750, 1650), PriceMW(500, nothing), PriceMW(200, 300), 
                PriceMW(100, 370), PriceMW(25, nothing)],
)
# nothing is because MW depends on the specific hour

# Reserve requirements

# link: https://www.nyiso.com/documents/20142/3694424/Locational-Reserves-Requirements.pdf
# VII SENY 30-minute total reserve is, depending on the hour, based on Reliability Rules that require the ability to restore a transmission circuit loading toEmergency or Normal TransferOperatingCriteria within30 minutes of thecontingency. The SENY 30-minutetotalreserve requirement will vary as follows: 
#(a) for hour beginning (HB) 00 through HB 5, the requirement is 1,300 M W; 
#(b) for HB 6, the requirement is 1,550 M W; 
#(c) for HB 7 through HB 21, the requirement is 1,800 M W; 
#(d) for HB 22, the requirement is 1,550 M W; and 
#(e) for HB 23, the requirement is 1,300 M W. 
SENY_reserve = [1300, 1300, 1300, 1300, 1300, 1300, 1550, 1800, 1800, 1800, 1800, 
1800, 1800, 1800, 1800, 1800, 1800, 1800, 1800, 1800, 1800, 1800, 1550, 1300]

# XI LI 30-minute total reserve is based on Reliability Rules that require the ability to restore a transmission circuit loading to Normal OperatingCriteria within 30 minutes of the contingency. 
# The LI 30-minute reserve requirement will vary from 270MWfor off-peak hours to
# 540MW for non-peak hours.
LI_reserve = [270, 270, 270, 270, 270, 270, 540, 540, 540, 540, 540, 540, 540, 
                540, 540, 540, 540, 540, 540, 540, 540, 540, 270, 270]
reserve_requirement_by_hour = Dict(
    "10Spin" => [985 for i in 1:24],
    "10Total" => [2630 for i in 1:24],
    "30Total" => SENY_reserve + LI_reserve .+(2620 + 1200 + 1000),
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
