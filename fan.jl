module Fan

using Util


const MIN_DUTY = 2

typealias Zone Int8

const system = Zone(0)
const peripheral = Zone(1)


typealias Mode Int8

const standard = Mode(0)
const full = Mode(1)
const optimal = Mode(2)
const heavyio = Mode(4)


function mode()
    output = readlines(`ipmitool raw 0x30 0x45 0x00`)
    @assert length(output) == 1
    strval = strip(output[1])
    return parse(Mode, strval)
end

function mode!(mode::Mode)
    run(pipeline(`ipmitool raw 0x30 0x45 0x01 0x$(hex(mode, 2))`, stdout=DevNull))
end


function duty(zone::Zone)
    output = readlines(`ipmitool raw 0x30 0x70 0x66 0x00 0x$(hex(zone, 2))`)
    @assert length(output) == 1
    strval = strip(output[1])
    return parse(Int, strval)
end

function duty!(zone::Zone, val)
    pct = trunc(Int, clamp(val, 0, 100))
    run(pipeline(`ipmitool raw 0x30 0x70 0x66 0x01 0x$(hex(zone, 2)) 0x$(hex(pct, 2))`, stdout=DevNull))
end


function limits!(fan::String, noncritical::SimpleRange{Int}, critical::SimpleRange{Int}, nonrecoverable::SimpleRange{Int})
    @assert noncritical.lower >= critical.lower >= nonrecoverable.lower
    @assert noncritical.upper <= critical.upper <= nonrecoverable.upper

    vals = Dict(
        "unr" => nonrecoverable.upper,
        "ucr" => critical.upper,
        "unc" => noncritical.upper,
        "lnc" => noncritical.lower,
        "lcr" => critical.lower,
        "lnr" => nonrecoverable.lower
    )
    run(pipeline(`ipmitool sensor thresh $fan lower $(vals["lnr"]) $(vals["lcr"]) $(vals["lnc"])`, stdout=DevNull))
    run(pipeline(`ipmitool sensor thresh $fan upper $(vals["unc"]) $(vals["ucr"]) $(vals["unr"])`, stdout=DevNull))
end


end
