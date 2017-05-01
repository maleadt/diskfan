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


immutable Reading
    timestamp::Float64
    value
end

"""
    Cache sensor readings over `window` amount of seconds, adding new readings once the
    current value expires after `expiry` seconds.

    Should be used with do-block syntax. The inner function should return a tuple consisting
    of the value, and a boolean indicating the validity of said value.

    Returns an array of valid `Reading`s, each containing the value and a timestamp.
"""
function cache(f::Function, id::String, expiry::Real, window::Real)
    now = time()

    # manage readings
    readings = get!(value_cache, id, Reading[])
    if isempty(readings) || (now-readings[end].timestamp) > expiry
        value, valid = f()
        valid && push!(readings, Reading(now, value))
    end
    filter!(reading->(now-reading.timestamp)<=window, readings)

    return readings
end
const value_cache = Dict{String,Vector{Reading}}()

"""
    Cache a single sensor reading until it expires after `expiry` seconds.
    Directly returns the value.
"""
cache(f::Function, id::String, expiry::Real) = cache(f, id, expiry, expiry)[1].value


"""
    Calculates a decaying average of a set of readings, controlling the amount of decay
    using the `constant` parameter (larger values result in more quickly vanishing values).
"""
function decay(readings::Vector{Reading}, window::Real, constant::Real=5)
    @assert constant >= 0
    now = time()

    # exponential decay (with t ∈ 0:1):
    #   reading(t)' = weight(t) * reading(t)
    #   weight(t) = e^(-t*decay)
    # but we normalize the weights in order to use a plain `sum` afterwards
    values = [reading.value for reading in readings]
    weights = [e^(-constant*(now-reading.timestamp)/window) for reading in readings]
    normalized_weights = [weight/sum(weights) for weight in weights]
    return sum(normalized_weights .* values)
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
