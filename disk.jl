module Disk

using Util


"""Resolve disk names to their block device name."""
function resolve!(disks)
    _disks = copy(disks)
    empty!(disks)
    for disk in _disks
        if isblockdev(joinpath("/dev", disk))
            push!(disks, disk)
        else
            found = false
            for dir in readdir("/dev/disk")
                path = joinpath("/dev/disk", dir, disk)
                islink(path) || continue
                push!(disks, basename(realpath(path)))
                found = true
            end
            found || error("Could not find disk $disk")
        end
    end
end


@enum Mode active standby sleeping

"""Determine the current power state of a disk, without waking it up."""
function power(device::String)
    # NOTE: we use smartctl, and not hdparm, because the latter wakes up disk from SLEEP
    #       https://serverfault.com/questions/275364/get-drive-power-state-without-waking-it-up
    cmd = ignorestatus(`smartctl -i -n idle /dev/$device`)
    output = readlines(cmd)

    for line in output
        m = match(r"Device is in (.+) mode", line)
        if m != nothing
            # FIXME: verify the exitcode of smartctl is 2
            mode = m.captures[1]
            if mode == "STANDBY"
                return standby
            elseif mode == "SLEEP"
                return sleeping
            else
                error("Unknown device mode '$mode'")
            end
        end
    end

    # at this point, the device should be active or idle, verify to make sure
    # FIXME: verify the exitcode of smartctl is 0
    for line in output
        m = match(r"Power mode is:\s+(.+)", line)
        if m != nothing
            mode = m.captures[1]
            if mode == "ACTIVE or IDLE"
                # FIXME: is smartctl ever able to discern between those two?
                return active
            else
                error("Unknown device mode '$mode'")
            end
        end
    end
end

"""Set the power state of a disk."""
function power!(device, mode::Mode)
    if mode == standby
        run(pipeline(`hdparm -y /dev/$device`, stdout=DevNull))
    elseif mode == sleeping
        run(pipeline(`hdparm -Y /dev/$device`, stdout=DevNull))
    end
end

const temp_cache = Dict{String,Tuple{Float64,Float64}}()

"""
   Determine the temperature of a disk in degrees.
   Caches values for 1 minute to prevent too many SMART queries.

   The `keep` argument determines what state we should not wake the device from.
   This defaults to SLEEP, as for most drives that's the state we can't read SMART
   attributes from without waking the drive.

   If the temperature cannot be read, NaN is returned.
"""
function temp(device, keep=sleeping)
    # NOTE: we use smartctl, and not hddtemp, because the latter wakes up drives.
    #       with smartctl, we can read from a drive in STANDBY (but not from SLEEP)
    Util.cache("$device.temp", 60) do
        # determine smartctl command
        nocheck = if keep == nothing
            "never"
        elseif keep == sleeping
            "sleep"
        elseif keep == standby
            "standby"
        elseif keep == active
            "idle"
        else
            error("invalid wake threshold '$wake_threshold'")
        end
        cmd = ignorestatus(`smartctl -A -n $nocheck /dev/$device`)

        # read attributes
        attributes = Dict{Int, Vector{String}}()
        at_list = false
        for line in eachline(cmd)
            line = chomp(line)
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
        if haskey(attributes, 194)
            return parse(Int, attributes[194][9])
        elseif haskey(attributes, 231)
            return parse(Int, attributes[231][9])
        else
            warn("Could not find SMART attribute for disk temperature")
            return NaN
        end
    end
end

const diskstats = Dict{String,Vector{Vector{Int}}}()

"""Monitor disk usage statistics. See `usage(device)`."""
function monitor_usage()
    global diskstats
    while true
        for line in eachline("/proc/diskstats")
            entries = split(line)
            device = entries[3]
            stats = map(str->parse(Int,str), entries[4:end])

            # save up to 15 sets of stats
            all_stats = get!(diskstats, device, Vector{Vector{Int}}())
            push!(all_stats, stats)
            if length(all_stats) > 15
                shift!(all_stats)
            end
        end

        sleep(60)
    end
end

"""
   Return the usage of a disk, based on the measurements of `monitor_usage()`.

   Returns a (load-average style) tuple of 3 values, (1min, 5min, 15min), where each value
   represents an indicator of usage (currently: sectors read/written + I/Os in progress)
   or nothing when not enough data has been collected yet.
"""
function usage(device)
    all_stats = get(diskstats, device, Vector{Vector{Int}}())

    function avg_stats(window)
        length(all_stats) >= window || return nothing
        stats = all_stats[end-window+1:end]

        reads =  stats[end][3] - stats[1][3]    # NOTE: we use sectors, as some writes
        writes = stats[end][7] - stats[1][7]    #       don't hit the device (immediately)
        busy =   stats[end][9]
        return reads+writes+busy
    end

    return avg_stats(1), avg_stats(5), avg_stats(15)
end


end
