module Util

export range_scale, @trace

# FIXME: replace with an additional log level
macro trace(ex...)
    esc(:(@debug $(ex...)))
end

struct Reading{T<:Real}
    timestamp::Float64
    value::T
end

Base.eltype(::Type{Reading{T}}) where {T} = T

"""
    Cache sensor readings over `window` amount of seconds, adding new readings once the
    current value expires after `expiry` seconds.

    Should be used with do-block syntax. The inner function should return a real, or
    `nothing` if no valid value could be acquired.

    Returns an array of valid `Reading`s, each containing the value and a timestamp.
"""
function cache(f::Function, id::String, expiry::Real, window::Real)
    now = time()

    # if this is the very first cache entry, we need a value in order to create a cache with
    # the proper type (eg. Vector{Reading{Float64}} instead of Vector{Reading})
    value = missing
    if !haskey(value_cache, id)
        value = f()
        T = eltype(value)
        value_cache[id] = Reading{T}[]
    end

    # get and prune readings
    readings = value_cache[id]
    filter!(reading->(now-reading.timestamp)<=window, readings)

    # add new entries
    if isempty(readings) || (now-readings[end].timestamp) > expiry
        if value === missing
            # we might have read a value already, to populate value_cache
            value = f()
        end

        if value !== nothing
            push!(readings, Reading(now, value))
        end
    end

    return readings
end
const value_cache = Dict{String,Vector}()

"""
    Cache a single sensor reading until it expires after `expiry` seconds.

    Returns `nothing` if no non-expired value could be acquired.
"""
function cache(f::Function, id::String, expiry::Real)
    readings = cache(f, id, expiry, expiry)
    if isempty(readings)
        return nothing
    else
        @assert length(readings) == 1
        return readings[1].value
    end
end


"""
    Calculates a decaying average of a set of readings, controlling the amount of decay
    using the `constant` parameter (larger values result in more quickly vanishing values).
"""
function decay(readings::Vector{Reading{T}}, window::Real, constant::Real=5)::Union{Nothing,T} where {T}
    @assert constant >= 0
    now = time()

    if isempty(readings)
        return nothing
    end

    # exponential decay (with t ∈ 0:1):
    #   reading(t)' = weight(t) * reading(t)
    #   weight(t) = e^(-t*decay)
    # but we normalize the weights in order to use a plain `sum` afterwards
    values = [reading.value for reading in readings]
    weights = [ℯ^(-constant*(now-reading.timestamp)/window) for reading in readings]
    normalized_weights = [weight/sum(weights) for weight in weights]
    value = convert(T, sum(normalized_weights .* values))

    return value
end

cache_and_decay(f::Function, id::String, expiry::Real, window::Real, constant::Real=5) =
    decay(cache(f, id, expiry, window), window, constant)


"""Scale a value from one range to another.

   For example, `range_scale(35, 30:60, 0:100)` can be used to determine the required fan speed
   for a sensor at 35 degrees, requesting 0% duty for 30 degrees and 100% for 60 degrees.
"""
function range_scale(value, from::UnitRange, to::UnitRange)
    from_range = from.stop - from.start
    to_range = to.stop - to.start
    value = clamp(value, from.start, from.stop)
    return to.start + (value-from.start) * to_range/from_range
end


"""Run a command, passing the process and its streams to a lambda (use with do-block)."""
function execute(f::Function, cmd::Base.AbstractCmd, in=devnull)
    out = Pipe()
    err = Pipe()

    proc = run(pipeline(cmd, stdin=in, stdout=out, stderr=out); wait=false)

    close(out.in)
    close(err.in)

    try
        return f(proc, out, err)
    finally
        close(out)
        close(err)
    end
end


end
