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
    proc, out, _ = Util.output_proc(`smartctl -i -n idle /dev/$device`)
    wait(proc)
    output = readlines(out)

    for line in output
        m = match(r"Device is in (.+) mode", line)
        if m != nothing
            @assert proc.exitcode == 2
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
    @assert proc.exitcode == 0
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
const diskstats = Dict{String,Vector{Vector{Int}}}()

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
