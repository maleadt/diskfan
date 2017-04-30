module Cooling

using Util
import Util: debug, trace
using Sensors

export disk, cpu


"""
    Query the current air temperature. This is used to determine when to cool.
"""
function air_temperature()::Float64
    temps = filter(temp->!isnan(temp) && 0 <= temp <= 35, Sensors.ext())
    if isempty(temps)
        # sensible default
        return 25
    else
        return minimum(temps)
    end
end

"""Determine the required fan duty cycle to cool disks."""
function disk(disks)
    temps = filter(temp->!isnan(temp), map(Sensors.disk, disks))
    if isempty(temps)
        warn("Could not query temperature of ", join(disks, ", ", " or "))
        0
    else
        temp = maximum(temps)

        # try to keep disks between 30 and 40 degrees Celsius
        base_temp = max(floor(Int, air_temperature()), 30)
        duty = range_scale(temp, base_temp:40, 0:100)
        trace("Disk(s) ", join(disks, ", ", " and "), " require cooling at $(round(duty, 2))%")
        return duty
    end
end

"""Determine the required fan duty cycle to cool the CPU."""
function cpu()
    temp = Sensors.cpu()

    # try to keep the CPU between 40 and 70 degrees Celsius
    base_temp = max(floor(Int, air_temperature()), 40)
    duty = range_scale(temp, base_temp:70, 0:100)
    trace("CPU requires cooling at $(round(duty, 2))%")
    duty
end


end
