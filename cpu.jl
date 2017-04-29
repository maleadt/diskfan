module CPU


# NOTE: we don't use IPMI here because spawning a command for every sensor read is costly

const sysfs_thermal = "/sys/class/thermal"

# find out which thermal zone is the CPU's
for entry in readdir(sysfs_thermal)
    startswith(entry, "thermal_zone") || continue

    path = joinpath(sysfs_thermal, entry, "type")
    isfile(path) || continue

    thermal_type = chomp(readline(path))
    thermal_type == "x86_pkg_temp" || continue

    isdefined(:cpu_zone) && error("Multiple CPU thermal zones")
    global const cpu_zone = entry
end
isdefined(:cpu_zone) || error("Could not find CPU thermal zone")

function temp()
    strval = readline(joinpath(sysfs_thermal, cpu_zone, "temp"))
    return parse(Int, strval) / 1000
end


end