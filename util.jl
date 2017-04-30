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


end
