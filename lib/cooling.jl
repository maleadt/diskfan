module Cooling

using Util
import Util: debug, trace
using Sensors

export disk, cpu


"""
    Query the current air temperature. This is used to determine when to cool.
"""
function air_temperature()::Float64
    temp = Sensor.ext()
    if !isnull(temp) && 0 < get(temp) <= 40
        return temp
    else
        return Nullable{Float64}()
    end
end

"""Calculate fan duty cycle to keep a device within a temperature range."""
function duty(device::String, temp::Real, target::UnitRange{<:Real})
    air_temp = Sensors.ext()
    T = promote_type(eltype(air_temp), eltype(target))

    if temp < target.start
        trace("No cooling required for $device")
        return 0
    elseif isnull(air_temp)
        # cannot adjust the temperature, so just rely on the target
        duty = range_scale(temp, target, 0:100)
        trace("Cooling $device (unknown air temperature) requires fans at $(round(duty,1))%")
        return duty
    elseif temp <= get(air_temp)
        warn("Cannot cool $device: air temperature of $(round(get(air_temp),1))°C "*
             "exceeds lower-bound temperature of $(round(target.start,1))°C")
        return 0
    else
        # adjust the target range to compensate for an air temperature > target lower bound
        # (eg. if we aim for 30:50 with air at 39, it doesn't make sense to cool a 40 degree
        # device with a fan at 50% duty cycle)
        adjusted_target = UnitRange(convert(T, max(get(air_temp), target.start)),
                                    convert(T, target.stop))
        duty = range_scale(temp, adjusted_target, 0:100)
        trace("Cooling $device requires fans at $(round(duty,1))%")
        return duty
    end
end


"""
    Determine the required fan duty cycle to cool disks.
    Tries to keep each disk between 30 and 40 degrees Celsius.
"""
function disk(disks::Vector{String})
    temps = map(get, filter(temp->!isnull(temp), map(Sensors.disk, disks)))
    if isempty(temps)
        warn("Could not query temperature of ", join(disks, ", ", " or "))
        return 100
    else
        return duty("disk(s) "*join(disks, ", ", " and "), maximum(temps), 30:40)
    end
end

"""
    Determine the required fan duty cycle to cool the CPU.
    Tries to keep the CPU between 40 and 70 degrees Celsius.
"""
function cpu()
    temp = Sensors.cpu()
    if isnull(temp)
        warn("Could not read CPU sensor")
        return 100
    else
        return duty("CPU", get(temp), 40:70)
    end
end


end
