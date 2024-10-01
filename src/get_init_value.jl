function _get_init_value_for_UC(sys::System; 
        ed_model::Union{JuMP.Model, Nothing} = nothing, 
        uc_model::Union{JuMP.Model, Nothing} = nothing, 
        uc_sol::Union{OrderedDict, Nothing} = nothing,
        ed_sol::Union{OrderedDict, Nothing} = nothing,
        init_fr_file_flag::Bool = false,
        init_fr_ED_flag::Bool = false,
        )::UCInitValue
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    if  init_fr_ED_flag # Initiate from scratch
        @info "Obtain initial conditions by running an ED model"
        ug_t0, Pg_t0, eb_t0 = _init_fr_ed_model(sys)
        history_vg = Dict(g => zeros(24) for g in thermal_gen_names)
        history_wg = Dict(g => zeros(8) for g in thermal_gen_names)
        return UCInitValue(ug_t0, Pg_t0, eb_t0, history_vg, history_wg)
    elseif init_fr_file_flag # Initiate from solution
        @info "Obtain initial conditions from existing solution files"
        ug_t0 = Dict(g => uc_sol["Commitment status"][g][end] for g in thermal_gen_names)
        Pg_t0 = Dict(g => ed_sol["Generator energy dispatch"][g][end][end] for g in thermal_gen_names)
        eb_t0 = Dict(b => ed_sol["Storage energy"][b][end][end] for b in storage_names)
        history_wg = Dict(g => uc_sol["Shut down"][g][end-7:end] for g in thermal_gen_names)
        history_vg = Dict(g => uc_sol["Start up"][g][end-23:end] for g in thermal_gen_names)
        return UCInitValue(ug_t0, Pg_t0, eb_t0, history_vg, history_wg)
    elseif length(all_variables(uc_model)) > 0 && length(all_variables(ed_model)) > 0 # Initiate from model
        @info "Obtain initial conditions from existing model"
        history_wg = uc_model[:init_value].history_wg
        history_vg = uc_model[:init_value].history_vg
        thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
        ug_t0 = Dict(g => value(uc_model[:ug][g,1]) for g in thermal_gen_names)
        #Get Pg_t0 and eb_t0 from ED model
        Pg_t0, eb_t0 = _get_binding_value_from_ED(sys, ed_model)
        for g in thermal_gen_names
            _push_fix_len_vector!(history_vg[g], Int(round(value(uc_model[:vg][g,1]), digits = 0)))
            _push_fix_len_vector!(history_wg[g], Int(round(value(uc_model[:wg][g,1]), digits = 0)))
        end
        return UCInitValue(ug_t0, Pg_t0, eb_t0, history_vg, history_wg)
    else
        error("The initial value is not properly set")
        return nothing
    end
end

function _push_fix_len_vector!(vec::Vector, val)
    popfirst!(vec)
    push!(vec, val)
end

function _init_fr_ed_model(sys::System; theta::Union{Nothing, Int64} = nothing)
    @info "Running ED model for the first time to get ug_t0"
    model = stochastic_ed(sys, Gurobi.Optimizer; uc_op_price = [0,0], theta = theta, start_time = DateTime(2018,12,31,21))
    thermal_gen_names = get_name.(get_components(ThermalGen, sys))
    storage_names = get_name.(get_components(GenericBattery, sys))
    pg_lim = Dict(g => get_active_power_limits(get_component(ThermalGen, sys, g)) for g in thermal_gen_names)
    Pg_t00 = Dict()
    ug_t0 = Dict()
    for g in thermal_gen_names
        val = value(model[:pg][g,1,1])
        if val > 0
            ug_t0[g] = 1
            Pg_t00[g] = max(val, pg_lim[g].min)
        else
            ug_t0[g] = 0
            Pg_t00[g] = 0
        end
    end
    eb_t0 = Dict(b => get_initial_energy(get_component(GenericBattery, sys, b)) for b in storage_names)
    wg_t0 = Dict(g => 0 for g in thermal_gen_names)
    vg_t0 = Dict(g => 0 for g in thermal_gen_names)
    ED_init_value = EDInitValue(ug_t0, vg_t0, wg_t0,Pg_t00, eb_t0)
    @info "Running ED model for the second time to get Pg_t0" 
    model = stochastic_ed(sys, Gurobi.Optimizer; uc_op_price =[0,0], init_value = ED_init_value, theta = theta, start_time = DateTime(2018,12,31,21))
    Pg_t0 = Dict(g => value(model[:pg][g,1,1]) for g in thermal_gen_names)
    return ug_t0, Pg_t0, eb_t0
end


function _get_binding_value_from_ED(sys::System, ed_model::JuMP.Model)
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    Pg_t0 = Dict(g => value(ed_model[:pg][g,1,1]) for g in thermal_gen_names)
    eb_t0 = Dict(b => value(ed_model[:eb][b,1,1]) for b in storage_names)
    return Pg_t0, eb_t0
end

function _get_init_value_for_ED(sys::System, uc_status::Vector;
    ed_model::Union{Nothing,JuMP.Model} = nothing, 
    UC_init_value::Union{Nothing,UCInitValue} = nothing,
    )::EDInitValue
    ug_t0 = uc_status[1]
    vg_t0 = uc_status[2]
    wg_t0 = uc_status[3]
    if !isnothing(ed_model) # Priority is initiating from the ED model
        Pg_t0, eb_t0 = _get_binding_value_from_ED(sys, ed_model)
        return EDInitValue(ug_t0, vg_t0, wg_t0, Pg_t0, eb_t0)  
    else
        Pg_t0 = UC_init_value.Pg_t0
        eb_t0 = UC_init_value.eb_t0
        return EDInitValue(ug_t0, vg_t0, wg_t0, Pg_t0, eb_t0)
    end
end


function _get_binary_status_for_ED(uc_model::JuMP.Model, thermal_gen_names; CoverHour = 2)
    ug_t0 = Dict(g => [Int(round(value(uc_model[:ug][g,t]), digits=0)) for t in 1:CoverHour] for g in thermal_gen_names)
    vg_t0 = Dict(g => [Int(round(value(uc_model[:vg][g,t]), digits=0)) for t in 1:CoverHour] for g in thermal_gen_names)
    wg_t0 = Dict(g => [Int(round(value(uc_model[:wg][g,t]), digits=0)) for t in 1:CoverHour] for g in thermal_gen_names)
    return [ug_t0, vg_t0, wg_t0]
end



function init_rolling_uc(sys::System; theta::Union{Nothing, Int64} = nothing, solution_file = nothing)
    if isnothing(solution_file)
        init_value = _get_init_value_for_UC(sys, theta)
        solution = _initiate_solution_uc_t(sys)
    else     
        solution = read_json(solution_file)
        init_value = _get_init_value_for_UC(sys, solution)
    end
    return init_value, solution
end

#TODO
function _get_init_value_for_UC(sys::System, solution::OrderedDict)::UCInitValue
    storage_names = PSY.get_name.(get_components(GenericBattery, sys))
    thermal_gen_names = PSY.get_name.(get_components(ThermalGen, sys))
    history_wg = Dict(g => solution["Shut down"][g] for g in thermal_gen_names)
    history_vg = Dict(g => solution["Start up"][g] for g in thermal_gen_names)
    ug_t0 = Dict(g => solution["Commitment status"][g][end] for g in thermal_gen_names)
    Pg_t0 = Dict(g => solution["Generator energy dispatch"][g][end] for g in thermal_gen_names)
    eb_t0 = Dict(b => solution["Batter energy"][b][end] for b in storage_names)
    return UCInitValue(ug_t0, Pg_t0, eb_t0, history_vg, history_wg)
end