module Util


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


end
