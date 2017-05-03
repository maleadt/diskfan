module Util

export range_scale


const TRACE = haskey(ENV, "TRACE")
@inline function trace(io::IO, msg...; prefix="TRACE: ")
    TRACE && print_with_color(:cyan, io, prefix, string(msg...), "\n")
end
@inline trace(msg...; kwargs...) = trace(STDERR, msg...; kwargs...)


const DEBUG = TRACE || haskey(ENV, "DEBUG")
@inline function debug(io::IO, msg...; prefix="DEBUG: ")
    DEBUG && print_with_color(:green, io, prefix, string(msg...), "\n")
end
@inline debug(msg...; kwargs...) = debug(STDERR, msg...; kwargs...)


immutable Reading{T<:Real}
    timestamp::Float64
    value::T
end

Base.eltype(::Type{Reading{T}}) where {T} = T

"""
    Cache sensor readings over `window` amount of seconds, adding new readings once the
    current value expires after `expiry` seconds.

    Should be used with do-block syntax. The inner function should return a nullable real,
    indicating whether a valid value could be acquired.

    Returns an array of valid `Reading`s, each containing the value and a timestamp.
"""
function cache(f::Function, id::String, expiry::Real, window::Real)
    now = time()

    # if this is the very first cache entry, we need a value in order to create a cache with
    # the proper type (eg. Vector{Reading{Float64}} instead of Vector{Reading})
    value = nothing
    if !haskey(value_cache, id)
        value = f()::Nullable
        T = eltype(value)
        value_cache[id] = Reading{T}[]
    end

    # get and prune readings
    readings = value_cache[id]
    filter!(reading->(now-reading.timestamp)<=window, readings)

    # add new entries
    if isempty(readings) || (now-readings[end].timestamp) > expiry
        if value == nothing
            # we might have read a value already, to populate value_cache
            value = f()::Nullable
        end

        if !isnull(value)
            push!(readings, Reading(now, get(value)))
        end
    end

    return readings
end
const value_cache = Dict{String,Vector}()

"""
    Cache a single sensor reading until it expires after `expiry` seconds.

    Returns a nullable real, indicating whether a non-expired value could be acquired.
"""
function cache(f::Function, id::String, expiry::Real)
    readings = cache(f, id, expiry, expiry)
    if isempty(readings)
        return Nullable{eltype(eltype(readings))}()
    else
        @assert length(readings) == 1
        return Nullable(readings[1].value)
    end
end


"""
    Calculates a decaying average of a set of readings, controlling the amount of decay
    using the `constant` parameter (larger values result in more quickly vanishing values).
"""
function decay(readings::Vector{Reading{T}}, window::Real, constant::Real=5)::Nullable{T} where {T}
    @assert constant >= 0
    now = time()

    if isempty(readings)
        return Nullable{T}()
    end

    # exponential decay (with t ∈ 0:1):
    #   reading(t)' = weight(t) * reading(t)
    #   weight(t) = e^(-t*decay)
    # but we normalize the weights in order to use a plain `sum` afterwards
    values = [reading.value for reading in readings]
    weights = [e^(-constant*(now-reading.timestamp)/window) for reading in readings]
    normalized_weights = [weight/sum(weights) for weight in weights]
    value = convert(T, sum(normalized_weights .* values))

    return Nullable(value)
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


"""Run a command, returning the process and its output streams."""
function output_proc(cmd::Base.AbstractCmd, stdin=DevNull)
    stdout = Pipe()
    stderr = Pipe()

    proc = spawn(cmd, (stdin,stdout,stderr))

    close(stdout.in)
    close(stderr.in)

    return proc, stdout, stderr
end


end
