module Fan

# NOTE: the raw IPMI commands are for SuperMicro X9/X10/X11 hardware
#       https://forums.servethehome.com/index.php?resources/supermicro-x9-x10-x11-fan-speed-control.20/
#       tested on a SuperMicro X11SSH-F

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


"""Query the fan mode of a zone."""
function mode()
    output = readlines(`ipmitool raw 0x30 0x45 0x00`)
    @assert length(output) == 1
    strval = strip(output[1])
    return parse(Mode, strval)
end

"""Set the fan mode of a zone."""
function mode!(mode::Mode)
    run(pipeline(`ipmitool raw 0x30 0x45 0x01 0x$(hex(mode, 2))`, stdout=DevNull))
end


"""Query the requested fan duty cycle of a zone."""
function duty(zone::Zone)
    output = readlines(`ipmitool raw 0x30 0x70 0x66 0x00 0x$(hex(zone, 2))`)
    @assert length(output) == 1
    strval = strip(output[1])
    return parse(Int, strval)
end

"""
   Set the requested fan duty cycle of a zone.
   This might need the current mode to be `full`.
"""
function duty!(zone::Zone, val)
    pct = trunc(Int, clamp(val, 0, 100))
    run(pipeline(`ipmitool raw 0x30 0x70 0x66 0x01 0x$(hex(zone, 2)) 0x$(hex(pct, 2))`, stdout=DevNull))
end


end
