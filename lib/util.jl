module Util

export range_scale


const TRACE = haskey(ENV, "TRACE")
@inline function trace(io::IO, msg...; prefix="TRACE: ")
    TRACE && print_with_color(:cyan, io, prefix, chomp(string(msg...)), "\n")
end
@inline trace(msg...; kwargs...) = trace(STDERR, msg...; kwargs...)


const DEBUG = TRACE || haskey(ENV, "DEBUG")
@inline function debug(io::IO, msg...; prefix="DEBUG: ")
    DEBUG && print_with_color(:green, io, prefix, chomp(string(msg...)), "\n")
end
@inline debug(msg...; kwargs...) = debug(STDERR, msg...; kwargs...)


"""
    Cache a value for a given time. Returns the cached value within that timeout.

    To be used with do-block syntax.
"""
function cache(f::Function, id::String, timeout)
    now = time()
    if haskey(value_cache, id) && (now-value_cache[id][1]) < timeout
        return value_cache[id][2]
    else
        value = f()
        value_cache[id] = (now, value)
        return value
    end
end
const value_cache = Dict{String,Tuple{Float64,Any}}()


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


end
