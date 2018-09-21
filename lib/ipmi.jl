module IPMI


@enum Status ok critical nonrecoverable

function Base.parse(::Type{Status}, str)
    if str == "ok"
        return ok
    elseif str == "cr"
        return critical
    elseif str == "nr"
        return nonrecoverable
    end
end


struct Reading{T}
    value::T
    unit::AbstractString
    status::Status

    noncritical::Union{Nothing,UnitRange{T}}
    critical::Union{Nothing,UnitRange{T}}
    nonrecoverable::Union{Nothing,UnitRange{T}}
end


"""
   Decode the output of `ipmitool sensor list`, listing hardware sensors, their unit,
   current value, and configured limits.
"""
function sensors()
    data = Dict{String,Reading}()

    for line in eachline(`ipmitool sensor list`)
        entries = map(strip, split(line, '|'))
        @assert length(entries) == 10
        sensor, strval, unit, status = entries[1:4]
        strlimits = entries[5:end]

        # skip 
        strval == "na" && continue              # non-available sensors
        sensor == "Chassis Intru" && continue   # hard-to-parse sensors

        # figure out how to parse the output, and what to convert them to
        parse_type = missing
        if unit == "degrees C" || unit == "Volts"
            data_type = Float64
        elseif unit == "RPM"
            data_type = Int
            parse_type = Float64
        else
            error("Unknown unit for $sensor")
        end
        if parse_type === missing
            parse_type = data_type
        end

        # parse values
        function parse_value(parse_type, data_type, strval)
            if strval == "na"
                return NaN
            else
                return convert(data_type, parse(parse_type, strval))
            end
        end
        val = parse_value(parse_type, data_type, strval)
        limits = map(str->parse_value(parse_type, data_type, str), strlimits)

        # construct objects and save the data
        # NOTE: can't use `:` to construct UnitRange here, as eg. `colon(Float64, Float64)`
        #       constructs a `FloatRange` (which doesn't have a `stop`)
        lnr, lcr, lnc, unc, ucr, unr = limits
        data[sensor] = Reading(val, unit, parse(Status, status),
                               isnan(lnc) ? nothing : UnitRange{data_type}(lnc, unc),
                               isnan(lcr) ? nothing : UnitRange{data_type}(lcr, ucr),
                               isnan(lnr) ? nothing : UnitRange{data_type}(lnr, unr))
    end

    return data
end


"""Configure the limits of a sensor."""
function limits!(id::String, noncritical::UnitRange, critical::UnitRange, nonrecoverable::UnitRange)
    @assert noncritical.start >= critical.start >= nonrecoverable.start
    @assert noncritical.stop <= critical.stop <= nonrecoverable.stop

    vals = Dict(
        "unr" => nonrecoverable.stop,
        "ucr" => critical.stop,
        "unc" => noncritical.stop,
        "lnc" => noncritical.start,
        "lcr" => critical.start,
        "lnr" => nonrecoverable.start
    )
    run(pipeline(`ipmitool sensor thresh $id lower $(vals["lnr"]) $(vals["lcr"]) $(vals["lnc"])`, stdout=devnull))
    run(pipeline(`ipmitool sensor thresh $id upper $(vals["unc"]) $(vals["ucr"]) $(vals["unr"])`, stdout=devnull))
end


end
