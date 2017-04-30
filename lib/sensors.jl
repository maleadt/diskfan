module Sensors

using Util
import Util: debug, trace
using Disk


# find out which thermal zone is the CPU's
const sysfs_thermal = "/sys/class/thermal"
for entry in readdir(sysfs_thermal)
    startswith(entry, "thermal_zone") || continue

    path = joinpath(sysfs_thermal, entry, "type")
    isfile(path) || continue

    thermal_type = readline(path)
    thermal_type == "x86_pkg_temp" || continue

    isdefined(:cpu_zone) && error("Multiple CPU thermal zones")
    global const cpu_zone = entry
end
isdefined(:cpu_zone) || error("Could not find CPU thermal zone")


"""Determine the temperature of the CPU, in degrees Celsius."""
function cpu()
    # NOTE: we don't use IPMI here because reading from sysfs is much more efficient
    #       (vs. spawning `ipmitool` and parsing its output)
    strval = readline(joinpath(sysfs_thermal, cpu_zone, "temp"))
    temp = parse(Int, strval) / 1000
    trace("CPU at $(round(temp,1))°C")
    return temp
end


"""
   Determine the temperature of a disk, in degrees Celsius.
   Caches values for 1 minute to prevent too many SMART queries.

   The `keep` argument determines what state we should not wake the device from.
   This defaults to SLEEP, as for most drives that's the state we can't read SMART
   attributes from without waking the drive.

   If the temperature cannot be read, NaN is returned.
"""
function disk(device, keep=Disk.sleeping)
    Util.cache("Sensors.disk.$device", 60) do
        # NOTE: we use smartctl, and not hddtemp, because the latter wakes up drives.
        #       with smartctl, we can read from a drive in STANDBY (but not from SLEEP)

        # determine smartctl command
        nocheck = if keep == nothing
            "never"
        elseif keep == Disk.sleeping
            "sleep"
        elseif keep == Disk.standby
            "standby"
        elseif keep == Disk.active
            "idle"
        else
            error("invalid wake threshold '$wake_threshold'")
        end
        cmd = ignorestatus(`smartctl -A -n $nocheck /dev/$device`)

        # read attributes
        attributes = Dict{Int, Vector{String}}()
        at_list = false
        for line in eachline(cmd)
            isempty(line) && continue
            if ismatch(r"Device is in (.+) mode", line)
                return NaN
            elseif startswith(line, "ID#")
                at_list = true
            elseif at_list
                entries = split(line)
                id = parse(Int, shift!(entries))
                attributes[id] = entries
            end
        end

        # check temperature attributes
        # FIXME: this isn't terribly robust (are these attributes the correct ones, etc)
        #        but it works for me
        temp = if haskey(attributes, 194)
            parse(Int, attributes[194][9])
        elseif haskey(attributes, 231)
            parse(Int, attributes[231][9])
        else
            warn("Could not find SMART attribute for disk temperature")
            return NaN
        end
        trace("Disk $(device) at $(round(temp,1))°C")
        return temp
    end
end


"""
   Determine the temperature of external sensors, in degrees Celsius.
   Caches values for 1 minute.
"""
function ext()
    Util.cache("Sensors.ext", 60) do
        temps = Vector{Float64}()
        for line in eachline(`digitemp_DS9097 -c /etc/digitemp.conf -q -a -o2`)
            elapsed, strval = split(line)
            temp = parse(Float64, strval)
            # TODO: what is the invalid sentinel value again? 88?
            push!(temps, temp)
        end
        trace("External sensor(s) at ", join(map(temp->round(temp,1), temps), ", ", " and "), "°C")
        temps
    end
end


end