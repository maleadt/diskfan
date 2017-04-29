module IPMI

using Util


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

immutable Reading{T}
    value::T
    unit::AbstractString
    status::Status

    noncritical::Union{Void,SimpleRange{T}}
    critical::Union{Void,SimpleRange{T}}
    nonrecoverable::Union{Void,SimpleRange{T}}
end

function sensors()
    data = Dict{String,Reading}()

    for line in readlines(`ipmitool sensor list`)
        entries = map(strip, split(line, '|'))
        @assert length(entries) == 10
        sensor, strval, unit, status = entries[1:4]
        strlimits = entries[5:end]

        # skip 
        strval == "na" && continue              # non-available sensors
        sensor == "Chassis Intru" && continue   # hard-to-parse sensors

        # figure out how to parse the output, and what to convert them to
        parse_type = nothing
        if unit == "degrees C" || unit == "Volts"
            data_type = Float64
        elseif unit == "RPM"
            data_type = Int
            parse_type = Float64
        else
            error("Unknown unit for $sensor")
        end
        if parse_type == nothing
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
        lnr, lcr, lnc, unc, ucr, unr = limits
        data[sensor] = Reading(val, unit, parse(Status, status),
                               isnan(lnc) ? nothing : SimpleRange{data_type}(lnc, unc),
                               isnan(lcr) ? nothing : SimpleRange{data_type}(lcr, ucr),
                               isnan(lnr) ? nothing : SimpleRange{data_type}(lnr, unr))
    end

    return data
end


end
