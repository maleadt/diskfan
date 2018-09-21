module Sensors

using ..Util
using ..Disk

# all these methods return single numbers, for sensor readings.
# if the value is null, a transient error occurred (ie. couldn't be read, try again later).
# for other errors, exceptions are thrown.
#
# the functions themselves are responsible for throttling requests.


# find out which thermal zone is the CPU's
const sysfs_thermal = "/sys/class/thermal"
const cpu_zone = Ref{String}()
for entry in readdir(sysfs_thermal)
    startswith(entry, "thermal_zone") || continue

    path = joinpath(sysfs_thermal, entry, "type")
    isfile(path) || continue

    thermal_type = readline(path)
    thermal_type == "x86_pkg_temp" || continue

    isassigned(cpu_zone) && error("Multiple CPU thermal zones")
    cpu_zone[] = entry
end
isassigned(cpu_zone) || error("Could not find CPU thermal zone")


"""Determine the temperature of the CPU, in degrees Celsius."""
function cpu()::Union{Nothing,Float64}
    # CPU temperature is quote finicky, so we use a decaying average
    Util.cache_and_decay("Sensors.cpu", 5, 60) do
        # NOTE: we don't use IPMI here because reading from sysfs is much more efficient
        #       (vs. spawning `ipmitool` and parsing its output)
        strval = readline(joinpath(sysfs_thermal, cpu_zone[], "temp"))
        temp = parse(Int, strval) / 1000
        @trace "CPU at $(round(temp; digits=1))°C"
        return temp
    end
end



"""
   Determine the temperature of a disk, in degrees Celsius.
   Caches values for 1 minute to prevent too many SMART queries.

   The `keep` argument determines what state we should not wake the device from.
   This defaults to SLEEP, as for most drives that's the state we can't read SMART
   attributes from without waking the drive.

   If the temperature cannot be read, NaN is returned.
"""
function disk(device::String, keep=Disk.sleeping)::Union{Nothing,Float64}
    Util.cache("Sensors.disk.$device", 60) do
        # we use smartctl, and not hddtemp, because the latter wakes up drives. with
        # smartctl, we can read from a drive in STANDBY (but not from SLEEP)

        # determine smartctl command
        nocheck = if keep === nothing
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

        # read SMART attributes with smartctl
        attributes = Util.execute(`smartctl -A -n $nocheck /dev/$device`) do proc, out, _
            wait(proc)

            # parse attributes
            attributes = Dict{Int, Vector{String}}()
            at_list = false
            for line in eachline(out)
                isempty(line) && continue
                if occursin(r"Device is in (.+) mode", line)
                    @assert proc.exitcode == 2
                    return nothing
                elseif startswith(line, "ID#")
                    at_list = true
                elseif at_list
                    entries = split(line)
                    id = parse(Int, popfirst!(entries))
                    attributes[id] = entries
                end
            end

            attributes
        end
        if attributes === nothing
            return nothing
        elseif isempty(attributes)
            error("could not parse attributes")
        end

        # check temperature attributes
        # FIXME: this isn't terribly robust (are these attributes the correct ones, etc)
        #        but it works for me
        temp = if haskey(attributes, 194)
            parse(Int, attributes[194][9])
        elseif haskey(attributes, 231)
            parse(Int, attributes[231][9])
        else
            error("Could not find SMART attribute for temperature of disk $device")
        end

        @trace "Disk $device at $(temp)°C"
        return convert(Float64, temp)
    end
end


"""
   Determine the temperature of an external sensor, in degrees Celsius.

   Caches values for 1 minute.
"""
function ext(id::Int=1)::Union{Nothing,Float64}
    if id < 1
        error("invalid sensor id")
    end

    Util.cache("Sensors.ext", 300) do
        # read all external sensors
        temps = Util.execute(`digitemp_DS9097 -c /etc/digitemp.conf -q -a -o2`) do proc, out, _
            temps = Vector{Float64}()
            if !success(proc)
                # probably a transient error (eg. some other process holding the serial port)
                return nothing
            end

            # parse lines
            temps = Vector{Float64}()
            for line in eachline(out)
                elapsed, strval = split(line)
                push!(temps, parse(Float64, strval))
            end

            @trace "External sensor(s) at $(join(map(temp->round(temp; digits=1), temps), ", ", " and "))°C"
            temps
        end
        if temps === nothing
            return nothing
        end

        # return a single temperature
        if id > length(temps)
            error("invalid sensor id (requested sensor $id, but only got $(length(temps)) sensors)")
        end
        temps[id]
    end
end


end
